module pipeline_backpress_demo #(
    parameter   DEPTH = 32,
    parameter   WIDTH = 16
) (
    input       clk,
    input       rstn,

    input   i_valid,     // 操作使能，
    output  i_ready,
    input   [$clog2(DEPTH)-1:0] i_addr,
    input   [WIDTH-1:0] i_ins,

    output  o_valid,
    input   o_ready,
    output  [WIDTH-1:0] o_data
);

    logic [WIDTH-1:0]   ins_p1;
    logic [$clog2(DEPTH)-1:0]   addr_p1,addr_p2;
    logic [WIDTH-1:0]   data_p1,data_p2;
    logic [WIDTH-1:0]   bypass_rdata_p1;    // 因为无法直接修改ram的rdata而对wdata进行打拍

    logic bypass_load;
    logic byp_rdata_valid;    // bp_data寄存器现在被写入，数据是有效的
    logic [3:0] mux_sel_p1;
    logic [DEPTH-1:0]   addr_accessed;
    logic addr_not_acc_p1;  // 该指令访问RAM的地址之前未被访问
    // 以前向传播来命名
    logic pipe_valid_p0,pipe_valid_p1,pipe_valid_p2;    
    logic pipe_ready_p0,pipe_ready_p1,pipe_ready_p2;

    logic ram_wen,ram_ren,ram_ren_q;
    logic [$clog2(DEPTH)-1:0]   ram_waddr,ram_raddr;
    logic [WIDTH-1:0]   ram_wdata,ram_rdata;
    logic [DEPTH-1:0]   addr_accessed_set_mask;
    logic bypass_p2_to_p0,bypass_p2_to_p1,bypass_p1_to_p0;
    logic   addr_p1p0_eq;
    logic   addr_p2p1_eq;
    logic  addr_p2p0_eq;
    logic cur_access;

// =============== pipeline ===============//
    assign  pipe_valid_p0 = i_valid;
    assign  pipe_ready_p2 = o_ready;

// valid的前向传播
    always_ff @(posedge clk) begin
        if(~rstn)
            pipe_valid_p1 <= 1'b0;
        else if(pipe_ready_p0)
            pipe_valid_p1 <= pipe_valid_p0;
    end

    always_ff @( posedge clk ) begin
        if(~rstn)
            pipe_valid_p2 <= 1'b0;
        else if(pipe_ready_p1)
            pipe_valid_p2 <= pipe_valid_p1;
    end

// ready的反向传播
    assign  pipe_ready_p1 = ~pipe_valid_p2 | pipe_ready_p2;
    assign  pipe_ready_p0 = ~pipe_valid_p1 | pipe_ready_p1;

// ================ ram ================== //

//  不需要，内部不用阻滞，直接写入即可
    assign  ram_wen = pipe_valid_p2 && pipe_ready_p2;
    assign  ram_waddr = addr_p2;
    assign  ram_wdata = data_p2;
// 读ram条件：
// 1.ram的该地址已被初始化
// 2.不需要bypass
    assign  ram_ren = pipe_valid_p0 && pipe_ready_p0 && addr_accessed[i_addr] && ~bypass_p2_to_p0 && ~bypass_p1_to_p0;   
    assign  ram_raddr = i_addr;

    always_ff @( posedge clk ) begin
        if(~rstn)
            ram_ren_q <= 1'b0;
        else
            ram_ren_q <= ram_ren;
    end

    ram_2p #(DEPTH,WIDTH)   u_ram
    (
        .clk(clk),
        
        .wen(ram_wen),
        .waddr(ram_waddr),
        .wdata(ram_wdata),
        .ren(ram_ren),
        .raddr(ram_raddr),
        .rdata(ram_rdata)
    );

// =============== pipeline E1 ============= //

    always_ff @( posedge clk ) begin 
        if(~rstn) begin
            addr_p1 <= {$clog2(DEPTH){1'b0}};
            ins_p1 <= {WIDTH{1'b0}};
            addr_not_acc_p1 <= 1'b0;
        end
        else if(pipe_valid_p0 && pipe_ready_p0) begin
            addr_p1 <= i_addr;
            ins_p1 <= i_ins;
            addr_not_acc_p1 <= ~addr_accessed[i_addr];
        end
    end


// =============== pipeline E2 ============= //

    mux_one_hot #(4,WIDTH) u_mux (
        .mux_in({bypass_rdata_p1,data_p2,ram_rdata,{WIDTH{1'b0}}}),
        .sel(mux_sel_p1),
        .mux_out(data_p1)
    );

    always_ff @(posedge clk) begin
        if(~rstn) begin
            addr_p2 <= {$clog2(DEPTH){1'b0}}; 
            data_p2 <= {WIDTH{1'b0}};
        end

        else if(pipe_valid_p1 && pipe_ready_p1) begin
            addr_p2 <= addr_p1;
            data_p2 <= data_p1 + ins_p1; 
        end
    end

// ============ forwarding ============== //

    always_ff @(posedge clk ) begin
        if(~rstn)
            bypass_rdata_p1 <= {WIDTH{1'b0}};
        else if(pipe_valid_p0 && pipe_ready_p0 && bypass_p2_to_p0)  // 检测到raddr == waddr时才使用此bp_data 
            bypass_rdata_p1 <= ram_wdata;
        else if(pipe_valid_p1 && ram_ren_q && ~pipe_ready_p1 && ~bypass_p2_to_p1)   // RAM产生读数据但是流水线停滞了
            bypass_rdata_p1 <= ram_rdata;
    end

// 加载bp_data_p1的情况
// 1. P2的数据转发到P0
// 2. RAM的读数据出来但是P1被反压 并且该数据不需要被P2转发
    assign  bypass_load = (pipe_valid_p0 && pipe_ready_p0 && bypass_p2_to_p0) || (pipe_valid_p1 && ram_ren_q && ~pipe_ready_p1 && ~bypass_p2_to_p1);

    always_ff @(posedge clk) begin
        if(~rstn)
            byp_rdata_valid <= 1'b0;
        else if(bypass_load)    //  如果写入bp_data_p1 就拉高
            byp_rdata_valid <= 1'b1;
        else if(pipe_valid_p1 && pipe_ready_p1)
            byp_rdata_valid <= 1'b0;
    end

// 仿真debug用
    logic   ram_rdata_block;
    assign  ram_rdata_block = pipe_valid_p1 && ram_ren_q && ~pipe_ready_p1;

    assign  addr_p2p0_eq = addr_p2 == i_addr;
    assign  addr_p1p0_eq = addr_p1 == i_addr;
    assign  addr_p2p1_eq = addr_p2 == addr_p1;
    assign  bypass_p1_to_p0 = addr_p1p0_eq && pipe_valid_p0 && pipe_valid_p1;
    assign  bypass_p2_to_p0 = addr_p2p0_eq && pipe_valid_p0 && pipe_valid_p2;
    assign  bypass_p2_to_p1 = addr_p2p1_eq && pipe_valid_p1 && pipe_valid_p2;

    assign  mux_sel_p1 = {byp_rdata_valid,bypass_p2_to_p1,ram_ren_q&&~bypass_p2_to_p1,addr_not_acc_p1};

// ============ ram_accessed ============ //

    assign  addr_accessed_set_mask = 1 << i_addr;
    always_ff @(posedge clk ) begin
        if(~rstn)
            addr_accessed <= {DEPTH{1'b0}};
        else if(pipe_valid_p0 && pipe_ready_p0)
            addr_accessed <= addr_accessed | addr_accessed_set_mask;
    end

// ============== output ================//

    assign  i_ready = pipe_ready_p0;
    assign  o_valid = pipe_valid_p2;
    assign  o_data = data_p2;

endmodule