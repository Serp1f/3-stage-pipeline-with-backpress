// 双端口ram，支持1读1写，读会有1个时钟延迟
module ram_2p #(
    parameter DEPTH = 32,
    parameter WIDTH = 32
) (
    input   clk,
    
    input   wen,
    input   [$clog2(DEPTH)-1:0] waddr,
    input   [WIDTH-1:0] wdata,

    input   ren,
    input   [$clog2(DEPTH)-1:0] raddr,
    output  [WIDTH-1:0] rdata
);

    reg [WIDTH-1:0] mem[0:DEPTH-1];
    reg [WIDTH-1:0] r_data;
    wire [WIDTH*DEPTH-1:0] mem_wire;
    genvar i;
    
    generate
        for(i=0;i<DEPTH;i=i+1) begin
            always @(posedge clk ) begin
                if(wen && i == waddr)
                    mem[i] <= wdata;
            end
        end
    endgenerate

    generate
        for(i=0;i<DEPTH;i=i+1) begin
            assign mem_wire[WIDTH*i+:WIDTH] = mem[i];   // 展平成线
        end
    endgenerate

    always @(posedge clk ) begin
        if(ren)
            r_data <= mem_wire[WIDTH*raddr+:WIDTH];
    end

    assign rdata = r_data;
    
endmodule