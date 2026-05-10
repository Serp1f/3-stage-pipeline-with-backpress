module tb_pipeline_backpress_demo (
);

    int global_seed = 12345;

    parameter   DEPTH = 8;
    parameter   WIDTH = 16;

    logic   clk;
    logic   rstn;

    logic   i_valid;
    logic   i_ready;
    logic   [$clog2(DEPTH)-1:0] addr;
    logic   [WIDTH-1:0] ins;

    logic   o_valid;
    logic   o_ready;
    logic   [WIDTH-1:0] data;

    logic   [DEPTH-1:0][WIDTH-1:0]  test_mem={{WIDTH{1'b0}}};
    int test_data_queue[$];   // pipeline的结果有延迟，用队列保序
    int test_addr_queue[$];

    always 
    #5  clk = ~clk;

    initial begin
        $urandom(global_seed);  // 设置全局随机数生成器种子
        clk = 0;
        rstn = 0;
        i_valid = 0;
        addr = 0;
        ins = 0;
    //    o_ready = 0;
    #30 rstn = 1;
    end

    always_ff @(posedge clk) begin
        o_ready <= $urandom() % 8 < 3;    // 3/8 的概率发生反压
    end

    initial begin
    #50 @(posedge clk) #1;
        for(int i=0;i<DEPTH;i=i+1) begin
            write_in(i,i);
        end
    $stop();
    #100;
        for(int i=0;i<100;i=i+1) begin
            write_in($urandom() % DEPTH,$urandom()%256);
            repeat($urandom() %3) begin
                @(posedge clk) #1;
            end
        end
    $stop();
    end

    pipeline_backpress_demo #(DEPTH,WIDTH) u_pipe
    (
        .clk(clk),
        .rstn(rstn),

        .i_valid(i_valid),
        .i_ready(i_ready),
        .i_addr(addr),
        .i_ins(ins),

        .o_valid(o_valid),
        .o_ready(o_ready),
        .o_data(data)
    );

// 随机反压发生器


    task automatic write_in(
        input  [$clog2(DEPTH)-1:0]  wr_addr,
        input   [WIDTH-1:0] wr_ins
    );
    begin
        i_valid = 1;
        addr = wr_addr;
        ins = wr_ins;
        test_mem[wr_addr] = test_mem[wr_addr] + wr_ins;
        test_addr_queue.push_back(wr_addr);
        test_data_queue.push_back(test_mem[wr_addr]);
        @(posedge clk);
        while (~i_ready) begin
            @(posedge clk);
        end
        #1;
        i_valid = 0;
        addr = 0;
        ins = 0;
    end
    endtask //automatic

    int qdata;
    int qaddr;
    always_ff @(posedge  clk) begin
        if(o_valid && o_ready) begin
            qdata = test_data_queue.pop_front();
            qaddr = test_addr_queue.pop_front();
            if(qdata != data)
                $error(" wrong number,in address %d: expect %d but given %d",qaddr,qdata,data);
        end
    end

endmodule