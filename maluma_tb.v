`timescale 1ns / 1ns

// TESTBENCH - mALUma IEEE-754 ALU
module mALUma_tb;

    reg clk, rst, start;
    reg [31:0] op_a, op_b;
    reg [2:0] op_code;
    reg mode_fp;
    reg round_mode;
    
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;
    
    mALUma maluma(
        .clk(clk),
        .rst(rst),
        .start(start),
        .op_a(op_a),
        .op_b(op_b),
        .op_code(op_code),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result),
        .valid_out(valid_out),
        .flags(flags)
    );
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // IEEE-754 Single Precision (32-bit)
    parameter [31:0] SP_ZERO_POS   = 32'h00000000;
    parameter [31:0] SP_ZERO_NEG   = 32'h80000000;
    parameter [31:0] SP_INF_POS    = 32'h7F800000;
    parameter [31:0] SP_INF_NEG    = 32'hFF800000;
    parameter [31:0] SP_NAN        = 32'h7FC00000;
    parameter [31:0] SP_ONE        = 32'h3F800000;
    parameter [31:0] SP_TWO        = 32'h40000000;
    parameter [31:0] SP_THREE      = 32'h40400000;
    parameter [31:0] SP_FIVE       = 32'h40A00000;
    parameter [31:0] SP_SIX        = 32'h40C00000;
    parameter [31:0] SP_EIGHT      = 32'h41000000;
    
    // IEEE-754 Half Precision (16-bit)
    parameter [15:0] HP_ZERO_POS   = 16'h0000;
    parameter [15:0] HP_ZERO_NEG   = 16'h8000;
    parameter [15:0] HP_INF_POS    = 16'h7C00;
    parameter [15:0] HP_INF_NEG    = 16'hFC00;
    parameter [15:0] HP_NAN        = 16'h7E00;
    parameter [15:0] HP_ONE        = 16'h3C00;
    parameter [15:0] HP_TWO        = 16'h4000;
    parameter [15:0] HP_THREE      = 16'h4200;
    parameter [15:0] HP_FIVE       = 16'h4500;
    parameter [15:0] HP_SIX        = 16'h4600;
    parameter [15:0] HP_EIGHT      = 16'h4800;
    
    task run_test;
        input [255:0] test_name;
        input [31:0] a_val, b_val;
        input [2:0] op;
        input mode;
        input [31:0] expected;
        begin
            test_count = test_count + 1;
            
            @(posedge clk);
            op_a = a_val;
            op_b = b_val;
            op_code = op;
            mode_fp = mode;
            round_mode = 0;
            
            rst = 1;
            @(posedge clk);
            rst = 0;
            @(posedge clk);
            
            start = 1;
            @(posedge clk);
            start = 0;
            
            wait(valid_out == 1);
            @(posedge clk);
            
            display_result(test_name, mode, a_val, b_val, result, expected, flags, op);
        end
    endtask
    
    task display_result;
        input [255:0] test_name;
        input mode;
        input [31:0] a_val, b_val, res_val, expected_val;
        input [4:0] flag_val;
        input [2:0] op;
        begin
            $display("\nTest #%0d: %0s", test_count, test_name);
            
            case(op)
                3'b000: $display("  Operación: SUMA");
                3'b001: $display("  Operación: RESTA");
                3'b010: $display("  Operación: MULTIPLICACIÓN");
                3'b011: $display("  Operación: DIVISIÓN");
            endcase
            
            $display("  Modo: %s", mode ? "Single (32-bit)" : "Half (16-bit)");
            
            if (mode) begin
                $display("  A        = 0x%h | E:%h M:%h", a_val, a_val[30:23], a_val[22:0]);
                $display("  B        = 0x%h | E:%h M:%h", b_val, b_val[30:23], b_val[22:0]);
                $display("  Resultado= 0x%h | E:%h M:%h", res_val, res_val[30:23], res_val[22:0]);
                $display("  Esperado = 0x%h | E:%h M:%h", expected_val, expected_val[30:23], expected_val[22:0]);
            end else begin
                $display("  A        = 0x%h", a_val[15:0]);
                $display("  B        = 0x%h", b_val[15:0]);
                $display("  Resultado= 0x%h", res_val[15:0]);
                $display("  Esperado = 0x%h", expected_val[15:0]);
            end
            
            if (flag_val != 0) begin
                $display("  Flags: %b", flag_val);
                if (flag_val[4]) $display("    - Inexact");
                if (flag_val[3]) $display("    - Invalid Operation");
                if (flag_val[2]) $display("    - Divide by Zero");
                if (flag_val[1]) $display("    - Overflow");
                if (flag_val[0]) $display("    - Underflow");
            end
            
            $display("  valid_out: %b", valid_out);
            
            if (mode) begin
                if (res_val == expected_val) begin
                    $display("  PASS");
                    pass_count = pass_count + 1;
                end else begin
                    if ((expected_val[30:23] == 8'hFF && expected_val[22:0] != 0) &&
                        (res_val[30:23] == 8'hFF && res_val[22:0] != 0)) begin
                        $display("  PASS (NaN)");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL");
                        fail_count = fail_count + 1;
                    end
                end
            end else begin
                if (res_val[15:0] == expected_val[15:0]) begin
                    $display("  PASS");
                    pass_count = pass_count + 1;
                end else begin
                    if ((expected_val[14:10] == 5'h1F && expected_val[9:0] != 0) &&
                        (res_val[14:10] == 5'h1F && res_val[9:0] != 0)) begin
                        $display("  PASS (NaN)");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL");
                        fail_count = fail_count + 1;
                    end
                end
            end
        end
    endtask
    
    initial begin
        $display("\n================================================================");
        $display("        TESTBENCH - mALUma IEEE-754 ALU");
        $display("================================================================\n");
        
        rst = 1;
        start = 0;
        op_a = 0;
        op_b = 0;
        op_code = 0;
        mode_fp = 1;
        round_mode = 0;
        repeat(3) @(posedge clk);
        rst = 0;
        @(posedge clk);
        
        $display("\n--- SINGLE PRECISION: OPERACIONES BÁSICAS ---");
        run_test("SP: 2.0 + 3.0 = 5.0", SP_TWO, SP_THREE, 3'b000, 1, SP_FIVE);
        run_test("SP: 5.0 - 3.0 = 2.0", SP_FIVE, SP_THREE, 3'b001, 1, SP_TWO);
        run_test("SP: 2.0 * 3.0 = 6.0", SP_TWO, SP_THREE, 3'b010, 1, SP_SIX);
        run_test("SP: 6.0 / 2.0 = 3.0", SP_SIX, SP_TWO, 3'b011, 1, SP_THREE);
        
        $display("\n--- SINGLE PRECISION: CASOS CON NaN ---");
        run_test("SP: NaN + 5.0 = NaN", SP_NAN, SP_FIVE, 3'b000, 1, SP_NAN);
        run_test("SP: 3.0 - NaN = NaN", SP_THREE, SP_NAN, 3'b001, 1, SP_NAN);
        run_test("SP: NaN * 2.0 = NaN", SP_NAN, SP_TWO, 3'b010, 1, SP_NAN);
        run_test("SP: 1.0 / NaN = NaN", SP_ONE, SP_NAN, 3'b011, 1, SP_NAN);
        
        $display("\n--- SINGLE PRECISION: CASOS CON INFINITO ---");
        run_test("SP: Inf + 5.0 = Inf", SP_INF_POS, SP_FIVE, 3'b000, 1, SP_INF_POS);
        run_test("SP: 3.0 - Inf = -Inf", SP_THREE, SP_INF_POS, 3'b001, 1, SP_INF_NEG);
        run_test("SP: Inf * 2.0 = Inf", SP_INF_POS, SP_TWO, 3'b010, 1, SP_INF_POS);
        run_test("SP: 5.0 / Inf = 0", SP_FIVE, SP_INF_POS, 3'b011, 1, SP_ZERO_POS);
        
        $display("\n--- SINGLE PRECISION: DIVISIÓN POR CERO ---");
        run_test("SP: 5.0 / 0 = Inf", SP_FIVE, SP_ZERO_POS, 3'b011, 1, SP_INF_POS);
        run_test("SP: -3.0 / 0 = -Inf", 32'hC0400000, SP_ZERO_POS, 3'b011, 1, SP_INF_NEG);
        run_test("SP: 0 / 0 = NaN", SP_ZERO_POS, SP_ZERO_POS, 3'b011, 1, SP_NAN);
        
        $display("\n--- SINGLE PRECISION: CEROS CON SIGNO ---");
        run_test("SP: +0 + +0 = +0", SP_ZERO_POS, SP_ZERO_POS, 3'b000, 1, SP_ZERO_POS);
        run_test("SP: +0 + -0 = +0", SP_ZERO_POS, SP_ZERO_NEG, 3'b000, 1, SP_ZERO_POS);
        run_test("SP: -0 + -0 = -0", SP_ZERO_NEG, SP_ZERO_NEG, 3'b000, 1, SP_ZERO_NEG);
        
        $display("\n--- HALF PRECISION: OPERACIONES BÁSICAS ---");
        run_test("HP: 3.0 + 5.0 = 8.0", {16'b0, HP_THREE}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, HP_EIGHT});
        run_test("HP: 5.0 - 3.0 = 2.0", {16'b0, HP_FIVE}, {16'b0, HP_THREE}, 3'b001, 0, {16'b0, HP_TWO});
        run_test("HP: 2.0 * 3.0 = 6.0", {16'b0, HP_TWO}, {16'b0, HP_THREE}, 3'b010, 0, {16'b0, HP_SIX});
        run_test("HP: 6.0 / 2.0 = 3.0", {16'b0, HP_SIX}, {16'b0, HP_TWO}, 3'b011, 0, {16'b0, HP_THREE});
        
        $display("\n--- HALF PRECISION: CASOS CON NaN ---");
        run_test("HP: NaN + 5.0 = NaN", {16'b0, HP_NAN}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, HP_NAN});
        run_test("HP: 3.0 - NaN = NaN", {16'b0, HP_THREE}, {16'b0, HP_NAN}, 3'b001, 0, {16'b0, HP_NAN});
        run_test("HP: NaN * 2.0 = NaN", {16'b0, HP_NAN}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, HP_NAN});
        run_test("HP: 1.0 / NaN = NaN", {16'b0, HP_ONE}, {16'b0, HP_NAN}, 3'b011, 0, {16'b0, HP_NAN});
        
        $display("\n--- HALF PRECISION: CASOS CON INFINITO ---");
        run_test("HP: Inf + 5.0 = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, HP_INF_POS});
        run_test("HP: 3.0 - Inf = -Inf", {16'b0, HP_THREE}, {16'b0, HP_INF_POS}, 3'b001, 0, {16'b0, HP_INF_NEG});
        run_test("HP: Inf * 2.0 = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, HP_INF_POS});
        run_test("HP: 5.0 / Inf = 0", {16'b0, HP_FIVE}, {16'b0, HP_INF_POS}, 3'b011, 0, {16'b0, HP_ZERO_POS});
        
        $display("\n--- HALF PRECISION: DIVISIÓN POR CERO ---");
        run_test("HP: 5.0 / 0 = Inf", {16'b0, HP_FIVE}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_INF_POS});
        run_test("HP: -3.0 / 0 = -Inf", {16'b0, 16'hC200}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_INF_NEG});
        run_test("HP: 0 / 0 = NaN", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_NAN});
        
        $display("\n--- HALF PRECISION: CEROS CON SIGNO ---");
        run_test("HP: +0 + +0 = +0", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_POS}, 3'b000, 0, {16'b0, HP_ZERO_POS});
        run_test("HP: +0 + -0 = +0", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_NEG}, 3'b000, 0, {16'b0, HP_ZERO_POS});
        run_test("HP: -0 + -0 = -0", {16'b0, HP_ZERO_NEG}, {16'b0, HP_ZERO_NEG}, 3'b000, 0, {16'b0, HP_ZERO_NEG});
        
        $display("\n--- SINGLE PRECISION: Inf / Inf = NaN ---");
        run_test("SP: Inf / Inf = NaN", SP_INF_POS, SP_INF_POS, 3'b011, 1, SP_NAN);
        run_test("SP: Inf / -Inf = NaN", SP_INF_POS, SP_INF_NEG, 3'b011, 1, SP_NAN);
        run_test("SP: -Inf / Inf = NaN", SP_INF_NEG, SP_INF_POS, 3'b011, 1, SP_NAN);
        run_test("SP: -Inf / -Inf = NaN", SP_INF_NEG, SP_INF_NEG, 3'b011, 1, SP_NAN);
        
        $display("\n--- SINGLE PRECISION: Inf +/- Inf ---");
        run_test("SP: Inf + Inf = Inf", SP_INF_POS, SP_INF_POS, 3'b000, 1, SP_INF_POS);
        run_test("SP: -Inf + -Inf = -Inf", SP_INF_NEG, SP_INF_NEG, 3'b000, 1, SP_INF_NEG);
        run_test("SP: Inf - Inf = NaN", SP_INF_POS, SP_INF_POS, 3'b001, 1, SP_NAN);
        run_test("SP: -Inf - -Inf = NaN", SP_INF_NEG, SP_INF_NEG, 3'b001, 1, SP_NAN);
        run_test("SP: Inf + -Inf = NaN", SP_INF_POS, SP_INF_NEG, 3'b000, 1, SP_NAN);
        run_test("SP: -Inf + Inf = NaN", SP_INF_NEG, SP_INF_POS, 3'b000, 1, SP_NAN);
        
        $display("\n--- HALF PRECISION: Inf / Inf = NaN ---");
        run_test("HP: Inf / Inf = NaN", {16'b0, HP_INF_POS}, {16'b0, HP_INF_POS}, 3'b011, 0, {16'b0, HP_NAN});
        run_test("HP: Inf / -Inf = NaN", {16'b0, HP_INF_POS}, {16'b0, HP_INF_NEG}, 3'b011, 0, {16'b0, HP_NAN});
        run_test("HP: -Inf / Inf = NaN", {16'b0, HP_INF_NEG}, {16'b0, HP_INF_POS}, 3'b011, 0, {16'b0, HP_NAN});
        run_test("HP: -Inf / -Inf = NaN", {16'b0, HP_INF_NEG}, {16'b0, HP_INF_NEG}, 3'b011, 0, {16'b0, HP_NAN});
        
        $display("\n--- HALF PRECISION: Inf +/- Inf ---");
        run_test("HP: Inf + Inf = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_INF_POS}, 3'b000, 0, {16'b0, HP_INF_POS});
        run_test("HP: -Inf + -Inf = -Inf", {16'b0, HP_INF_NEG}, {16'b0, HP_INF_NEG}, 3'b000, 0, {16'b0, HP_INF_NEG});
        run_test("HP: Inf - Inf = NaN", {16'b0, HP_INF_POS}, {16'b0, HP_INF_POS}, 3'b001, 0, {16'b0, HP_NAN});
        run_test("HP: -Inf - -Inf = NaN", {16'b0, HP_INF_NEG}, {16'b0, HP_INF_NEG}, 3'b001, 0, {16'b0, HP_NAN});
        run_test("HP: Inf + -Inf = NaN", {16'b0, HP_INF_POS}, {16'b0, HP_INF_NEG}, 3'b000, 0, {16'b0, HP_NAN});
        run_test("HP: -Inf + Inf = NaN", {16'b0, HP_INF_NEG}, {16'b0, HP_INF_POS}, 3'b000, 0, {16'b0, HP_NAN});
        
        $display("\n--- SINGLE PRECISION: NÚMEROS NEGATIVOS ---");
        run_test("SP: -5.0 * -3.0 = 15.0", 32'hC0A00000, 32'hC0400000, 3'b010, 1, 32'h41700000);
        run_test("SP: -6.0 / -2.0 = 3.0", 32'hC0C00000, 32'hC0000000, 3'b011, 1, SP_THREE);
        run_test("SP: 5.0 * -2.0 = -10.0", SP_FIVE, 32'hC0000000, 3'b010, 1, 32'hC1200000);
        
        $display("\n==============================================================");
        $display("                    RESUMEN FINAL");
        $display("================================================================");
        $display("Total de pruebas:     %0d", test_count);
        $display("Pruebas PASS:         %0d", pass_count);
        $display("Pruebas FAIL:         %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\nTodas las pruebas pasaron (100%%)");
        end else begin
            $display("\nPorcentaje de éxito: %.2f%%", (pass_count * 100.0) / test_count);
        end
        #10;
        $finish;
    end
    // Sólo si se compila en EDA Playground
    // initial begin
       // $dumpfile("maluma_test.vcd");
       // $dumpvars();
    // end

endmodule
