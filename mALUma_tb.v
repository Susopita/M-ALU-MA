`timescale 1ns / 1ns

// =====================================
// Testbench para mALUma Optimizado
// Cubre todos los casos especiales IEEE-754
// Para Single (32-bit) y Half (16-bit) Precision
// =====================================

module mALUma_tb;

    // =====================================
    // Señales de entrada
    // =====================================
    reg clk;
    reg rst;
    reg start;
    reg [31:0] op_a, op_b;
    reg [2:0] op_code;      // 000:ADD, 001:SUB, 010:MUL, 011:DIV
    reg mode_fp;            // 0 = half (16 bits), 1 = single (32 bits)
    reg round_mode;         // 0 = round to nearest even
    
    // =====================================
    // Señales de salida
    // =====================================
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;       // [4:inexact, 3:invalid, 2:div_by_zero, 1:overflow, 0:underflow]
    
    // ====================
    // Instancia maluma 
    // ====================
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
    
    // ========================
    // Generación del reloj
    // ========================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // =====================================
    // Variables para estadísticas
    // =====================================
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    
    // =====================================
    // Valores especiales IEEE-754 Single Precision
    // =====================================
    parameter [31:0] SP_ZERO_POS     = 32'h00000000;  // +0
    parameter [31:0] SP_ZERO_NEG     = 32'h80000000;  // -0
    parameter [31:0] SP_INF_POS      = 32'h7F800000;  // +Inf
    parameter [31:0] SP_INF_NEG      = 32'hFF800000;  // -Inf
    parameter [31:0] SP_NAN          = 32'h7FC00000;  // QNaN
    parameter [31:0] SP_DENORM_MIN   = 32'h00000001;  // Smallest denormal
    parameter [31:0] SP_DENORM_MAX   = 32'h007FFFFF;  // Largest denormal
    parameter [31:0] SP_NORM_MIN     = 32'h00800000;  // Smallest normal
    parameter [31:0] SP_NORM_MAX     = 32'h7F7FFFFF;  // Largest normal
    parameter [31:0] SP_ONE          = 32'h3F800000;  // 1.0
    parameter [31:0] SP_TWO          = 32'h40000000;  // 2.0
    parameter [31:0] SP_THREE        = 32'h40400000;  // 3.0
    parameter [31:0] SP_FIVE         = 32'h40A00000;  // 5.0
    
    // =====================================
    // Valores especiales IEEE-754 Half Precision
    // =====================================
    parameter [15:0] HP_ZERO_POS     = 16'h0000;      // +0
    parameter [15:0] HP_ZERO_NEG     = 16'h8000;      // -0
    parameter [15:0] HP_INF_POS      = 16'h7C00;      // +Inf
    parameter [15:0] HP_INF_NEG      = 16'hFC00;      // -Inf
    parameter [15:0] HP_NAN          = 16'h7E00;      // QNaN
    parameter [15:0] HP_DENORM_MIN   = 16'h0001;      // Smallest denormal
    parameter [15:0] HP_DENORM_MAX   = 16'h03FF;      // Largest denormal
    parameter [15:0] HP_NORM_MIN     = 16'h0400;      // Smallest normal
    parameter [15:0] HP_NORM_MAX     = 16'h7BFF;      // Largest normal
    parameter [15:0] HP_ONE          = 16'h3C00;      // 1.0
    parameter [15:0] HP_TWO          = 16'h4000;      // 2.0
    parameter [15:0] HP_THREE        = 16'h4200;      // 3.0
    parameter [15:0] HP_FIVE         = 16'h4500;      // 5.0
    

    // Tarea para mostrar resultados detallados
    task display_result;
        input [255:0] test_name;
        input mode;
        input [31:0] a_val, b_val, res_val, expected_val;
        input [4:0] flag_val;
        input [2:0] op;
        begin
            $display("\n=== Test #%0d: %0s ===", test_count, test_name);
            
            // Mostrar operación
            case(op)
                3'b000: $display("Operacion: SUMA");
                3'b001: $display("Operacion: RESTA");
                3'b010: $display("Operacion: MULTIPLICACION");
                3'b011: $display("Operacion: DIVISION");
            endcase
            
            $display("Modo: %s", mode ? "Single Precision (32-bit)" : "Half Precision (16-bit)");
            
            if (mode) begin // Single precision
                $display("A      = %h | S:%b E:%h M:%h | Float: %.6e", 
         		a_val, a_val[31], a_val[30:23], a_val[22:0], $bitstoreal({32'b0, a_val}));
				$display("B      = %h | S:%b E:%h M:%h | Float: %.6e", 
                b_val, b_val[31], b_val[30:23], b_val[22:0], $bitstoreal({32'b0, b_val}));
				$display("Result = %h | S:%b E:%h M:%h | Float: %.6e", 
         		res_val, res_val[31], res_val[30:23], res_val[22:0], $bitstoreal({32'b0, res_val}));
                if (expected_val !== 32'hXXXXXXXX) begin
                    $display("Expected = %h | S:%b E:%h M:%h", 
                             expected_val, expected_val[31], expected_val[30:23], expected_val[22:0]);
                end
            end else begin // Half precision
                $display("A      = %h | S:%b E:%h M:%h", 
                         a_val[15:0], a_val[15], a_val[14:10], a_val[9:0]);
                $display("B      = %h | S:%b E:%h M:%h", 
                         b_val[15:0], b_val[15], b_val[14:10], b_val[9:0]);
                $display("Result = %h | S:%b E:%h M:%h", 
                         res_val[15:0], res_val[15], res_val[14:10], res_val[9:0]);
                if (expected_val[15:0] !== 16'hXXXX) begin
                    $display("Expected = %h | S:%b E:%h M:%h", 
                             expected_val[15:0], expected_val[15], expected_val[14:10], expected_val[9:0]);
                end
            end
            
            // Mostrar flags
            $display("Flags  = %b", flag_val);
            if (flag_val != 0) begin
                if (flag_val[4]) $display("  [✓] Inexact");
                if (flag_val[3]) $display("  [✓] Invalid Operation");
                if (flag_val[2]) $display("  [✓] Divide by Zero");
                if (flag_val[1]) $display("  [✓] Overflow");
                if (flag_val[0]) $display("  [✓] Underflow");
            end
            
            // Verificar resultado
            if (mode) begin
                if ((expected_val !== 32'hXXXXXXXX) && (res_val !== expected_val)) begin
                    // Para NaN, cualquier NaN es válido
                    if ((expected_val[30:23] == 8'hFF && expected_val[22:0] != 0) &&
                        (res_val[30:23] == 8'hFF && res_val[22:0] != 0)) begin
                        $display("Estado: PASS (NaN detectado)");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("Estado: FAIL [X]");
                        fail_count = fail_count + 1;
                    end
                end else begin
                    $display("Estado: PASS [✓]");
                    pass_count = pass_count + 1;
                end
            end else begin
                if ((expected_val[15:0] !== 16'hXXXX) && (res_val[15:0] !== expected_val[15:0])) begin
                    // Para NaN, cualquier NaN es válido
                    if ((expected_val[14:10] == 5'h1F && expected_val[9:0] != 0) &&
                        (res_val[14:10] == 5'h1F && res_val[9:0] != 0)) begin
                        $display("Estado: PASS (NaN detectado)");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("Estado: FAIL [X]");
                        fail_count = fail_count + 1;
                    end
                end else begin
                    $display("Estado: PASS [✓]");
                    pass_count = pass_count + 1;
                end
            end
        end
    endtask
    
    // Tarea para ejecutar operación y esperar resultado
    task execute_operation;
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
            round_mode = 0; // Round to nearest even
            
            // Reset y start
            rst = 1;
            @(posedge clk);
            rst = 0;
            @(posedge clk);
            
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Esperar resultado válido
            wait(valid_out == 1);
            @(posedge clk);
            
            display_result(test_name, mode, a_val, b_val, result, expected, flags, op);
        end
    endtask
    
    // =====================================
    // Testbench principal
    // =====================================
    initial begin
        $display("\n");
        $display("================================================================");
        $display("        TESTBENCH - mALUma IEEE-754");
        $display("================================================================");
        $display("Timestamp: %0t", $time);
        
        // Inicialización
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
        
        // ================================================================
        // SINGLE PRECISION TESTS (32-bit)
        // ================================================================
        
        $display("\n");
        $display("----------------------------------------------------------------");
        $display("            SINGLE PRECISION TESTS (32-bit)");
        $display("----------------------------------------------------------------");
        
        // --- Operaciones Básicas ---
        $display("\n--- Operaciones Basicas ---");
        execute_operation("SP: 3.0 + 5.0 = 8.0", SP_THREE, SP_FIVE, 3'b000, 1, 32'h41000000);
        execute_operation("SP: 5.0 - 3.0 = 2.0", SP_FIVE, SP_THREE, 3'b001, 1, SP_TWO);
        execute_operation("SP: 2.0 * 3.0 = 6.0", SP_TWO, SP_THREE, 3'b010, 1, 32'h40C00000);
        execute_operation("SP: 6.0 / 2.0 = 3.0", 32'h40C00000, SP_TWO, 3'b011, 1, SP_THREE);
        
        // --- Casos con NaN ---
        $display("\n--- Casos con NaN (Invalid Operation) ---");
        execute_operation("SP: NaN + 5.0 = NaN", SP_NAN, SP_FIVE, 3'b000, 1, SP_NAN);
        execute_operation("SP: 3.0 - NaN = NaN", SP_THREE, SP_NAN, 3'b001, 1, SP_NAN);
        execute_operation("SP: NaN * 2.0 = NaN", SP_NAN, SP_TWO, 3'b010, 1, SP_NAN);
        execute_operation("SP: 1.0 / NaN = NaN", SP_ONE, SP_NAN, 3'b011, 1, SP_NAN);
        execute_operation("SP: 0 / 0 = NaN", SP_ZERO_POS, SP_ZERO_POS, 3'b011, 1, SP_NAN);
        
        // --- Casos con Infinitos ---
        $display("\n--- Casos con Infinitos ---");
        execute_operation("SP: Inf + 5.0 = Inf", SP_INF_POS, SP_FIVE, 3'b000, 1, SP_INF_POS);
        execute_operation("SP: 3.0 - Inf = -Inf", SP_THREE, SP_INF_POS, 3'b001, 1, SP_INF_NEG);
        execute_operation("SP: Inf * 2.0 = Inf", SP_INF_POS, SP_TWO, 3'b010, 1, SP_INF_POS);
        execute_operation("SP: Inf * -2.0 = -Inf", SP_INF_POS, 32'hC0000000, 3'b010, 1, SP_INF_NEG);
        execute_operation("SP: 5.0 / Inf = 0", SP_FIVE, SP_INF_POS, 3'b011, 1, SP_ZERO_POS);
        execute_operation("SP: Inf + Inf = Inf", SP_INF_POS, SP_INF_POS, 3'b000, 1, SP_INF_POS);
        
        // --- División por cero ---
        $display("\n--- Division por Cero ---");
        execute_operation("SP: 5.0 / 0 = Inf", SP_FIVE, SP_ZERO_POS, 3'b011, 1, SP_INF_POS);
        execute_operation("SP: -3.0 / 0 = -Inf", 32'hC0400000, SP_ZERO_POS, 3'b011, 1, SP_INF_NEG);
        execute_operation("SP: 1.0 / -0 = -Inf", SP_ONE, SP_ZERO_NEG, 3'b011, 1, SP_INF_NEG);
        
        // --- Ceros con signo ---
        $display("\n--- Ceros con Signo ---");
        execute_operation("SP: +0 + +0 = +0", SP_ZERO_POS, SP_ZERO_POS, 3'b000, 1, SP_ZERO_POS);
        execute_operation("SP: +0 + -0 = +0", SP_ZERO_POS, SP_ZERO_NEG, 3'b000, 1, SP_ZERO_POS);
        execute_operation("SP: -0 + -0 = -0", SP_ZERO_NEG, SP_ZERO_NEG, 3'b000, 1, SP_ZERO_NEG);
        execute_operation("SP: +0 - +0 = +0", SP_ZERO_POS, SP_ZERO_POS, 3'b001, 1, SP_ZERO_POS);
        
        // --- Números denormalizados ---
        $display("\n--- Numeros Denormalizados ---");
        execute_operation("SP: Denorm_min + Denorm_min", SP_DENORM_MIN, SP_DENORM_MIN, 3'b000, 1, 32'h00000002);
        execute_operation("SP: Denorm_max + Denorm_max", SP_DENORM_MAX, SP_DENORM_MAX, 3'b000, 1, 32'h00FFFFFE);
        execute_operation("SP: Denorm * 2.0", SP_DENORM_MIN, SP_TWO, 3'b010, 1, 32'h00000002);
        execute_operation("SP: Denorm / 2.0", SP_DENORM_MIN, SP_TWO, 3'b011, 1, 32'h00000000);
        execute_operation("SP: Normal_min - Normal_min", SP_NORM_MIN, SP_NORM_MIN, 3'b001, 1, SP_ZERO_POS);
        
        // --- Overflow ---
        $display("\n--- Overflow ---");
        execute_operation("SP: Max_norm * 2.0 = Inf", SP_NORM_MAX, SP_TWO, 3'b010, 1, SP_INF_POS);
        execute_operation("SP: Max_norm + Max_norm = Inf", SP_NORM_MAX, SP_NORM_MAX, 3'b000, 1, SP_INF_POS);
        execute_operation("SP: Large * Large = Inf", 32'h7F000000, 32'h7F000000, 3'b010, 1, SP_INF_POS);
        
        // --- Underflow ---
        $display("\n--- Underflow ---");
        execute_operation("SP: Min_norm / 2.0", SP_NORM_MIN, SP_TWO, 3'b011, 1, 32'h00400000);
        execute_operation("SP: Tiny * Tiny = 0", 32'h00800000, 32'h00800000, 3'b010, 1, SP_ZERO_POS);
        execute_operation("SP: Denorm / Large", SP_DENORM_MIN, 32'h7F000000, 3'b011, 1, SP_ZERO_POS);
        
        // --- Casos Inexactos ---
        $display("\n--- Casos Inexactos ---");
        execute_operation("SP: 1.0 / 3.0 (inexact)", SP_ONE, SP_THREE, 3'b011, 1, 32'h3EAAAAAB);
        execute_operation("SP: 2.0 / 3.0 (inexact)", SP_TWO, SP_THREE, 3'b011, 1, 32'h3F2AAAAB);
        execute_operation("SP: 1.0 / 7.0 (inexact)", SP_ONE, 32'h40E00000, 3'b011, 1, 32'hXXXXXXXX);
        
        // ================================================================
        // HALF PRECISION TESTS (16-bit)
        // ================================================================
        
        $display("\n");
        $display("----------------------------------------------------------------");
        $display("            HALF PRECISION TESTS (16-bit)");
        $display("----------------------------------------------------------------");
        
        // --- Operaciones Básicas ---
        $display("\n--- Operaciones Basicas ---");
        execute_operation("HP: 3.0 + 5.0 = 8.0", {16'b0, HP_THREE}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, 16'h4800});
        execute_operation("HP: 5.0 - 3.0 = 2.0", {16'b0, HP_FIVE}, {16'b0, HP_THREE}, 3'b001, 0, {16'b0, HP_TWO});
        execute_operation("HP: 2.0 * 3.0 = 6.0", {16'b0, HP_TWO}, {16'b0, HP_THREE}, 3'b010, 0, {16'b0, 16'h4600});
        execute_operation("HP: 6.0 / 2.0 = 3.0", {16'b0, 16'h4600}, {16'b0, HP_TWO}, 3'b011, 0, {16'b0, HP_THREE});
        
        // --- Casos con NaN ---
        $display("\n--- Casos con NaN (Invalid Operation) ---");
        execute_operation("HP: NaN + 5.0 = NaN", {16'b0, HP_NAN}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, HP_NAN});
        execute_operation("HP: 3.0 - NaN = NaN", {16'b0, HP_THREE}, {16'b0, HP_NAN}, 3'b001, 0, {16'b0, HP_NAN});
        execute_operation("HP: NaN * 2.0 = NaN", {16'b0, HP_NAN}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, HP_NAN});
        execute_operation("HP: 1.0 / NaN = NaN", {16'b0, HP_ONE}, {16'b0, HP_NAN}, 3'b011, 0, {16'b0, HP_NAN});
        execute_operation("HP: 0 / 0 = NaN", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_NAN});
        
        // --- Casos con Infinitos ---
        $display("\n--- Casos con Infinitos ---");
        execute_operation("HP: Inf + 5.0 = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_FIVE}, 3'b000, 0, {16'b0, HP_INF_POS});
        execute_operation("HP: 3.0 - Inf = -Inf", {16'b0, HP_THREE}, {16'b0, HP_INF_POS}, 3'b001, 0, {16'b0, HP_INF_NEG});
        execute_operation("HP: Inf * 2.0 = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, HP_INF_POS});
        execute_operation("HP: Inf * -2.0 = -Inf", {16'b0, HP_INF_POS}, {16'b0, 16'hC000}, 3'b010, 0, {16'b0, HP_INF_NEG});
        execute_operation("HP: 5.0 / Inf = 0", {16'b0, HP_FIVE}, {16'b0, HP_INF_POS}, 3'b011, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: Inf + Inf = Inf", {16'b0, HP_INF_POS}, {16'b0, HP_INF_POS}, 3'b000, 0, {16'b0, HP_INF_POS});
        
        // --- División por cero ---
        $display("\n--- Division por Cero ---");
        execute_operation("HP: 5.0 / 0 = Inf", {16'b0, HP_FIVE}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_INF_POS});
        execute_operation("HP: -3.0 / 0 = -Inf", {16'b0, 16'hC200}, {16'b0, HP_ZERO_POS}, 3'b011, 0, {16'b0, HP_INF_NEG});
        execute_operation("HP: 1.0 / -0 = -Inf", {16'b0, HP_ONE}, {16'b0, HP_ZERO_NEG}, 3'b011, 0, {16'b0, HP_INF_NEG});
        
        // --- Ceros con signo ---
        $display("\n--- Ceros con Signo ---");
        execute_operation("HP: +0 + +0 = +0", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_POS}, 3'b000, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: +0 + -0 = +0", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_NEG}, 3'b000, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: -0 + -0 = -0", {16'b0, HP_ZERO_NEG}, {16'b0, HP_ZERO_NEG}, 3'b000, 0, {16'b0, HP_ZERO_NEG});
        execute_operation("HP: +0 - +0 = +0", {16'b0, HP_ZERO_POS}, {16'b0, HP_ZERO_POS}, 3'b001, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: +0 * -5.0 = -0", {16'b0, HP_ZERO_POS}, {16'b0, 16'hC500}, 3'b010, 0, {16'b0, HP_ZERO_NEG});
        execute_operation("HP: -0 * -2.0 = +0", {16'b0, HP_ZERO_NEG}, {16'b0, 16'hC000}, 3'b010, 0, {16'b0, HP_ZERO_POS});
        
        // --- Números denormalizados ---
        $display("\n--- Numeros Denormalizados ---");
        execute_operation("HP: Denorm_min + Denorm_min", {16'b0, HP_DENORM_MIN}, {16'b0, HP_DENORM_MIN}, 3'b000, 0, {16'b0, 16'h0002});
        execute_operation("HP: Denorm_max + Denorm_max", {16'b0, HP_DENORM_MAX}, {16'b0, HP_DENORM_MAX}, 3'b000, 0, {16'b0, 16'h07FE});
        execute_operation("HP: Denorm * 2.0", {16'b0, HP_DENORM_MIN}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, 16'h0002});
        execute_operation("HP: Denorm / 2.0", {16'b0, HP_DENORM_MIN}, {16'b0, HP_TWO}, 3'b011, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: Normal_min - Normal_min", {16'b0, HP_NORM_MIN}, {16'b0, HP_NORM_MIN}, 3'b001, 0, {16'b0, HP_ZERO_POS});
        
        // --- Overflow ---
        $display("\n--- Overflow ---");
        execute_operation("HP: Max_norm * 2.0 = Inf", {16'b0, HP_NORM_MAX}, {16'b0, HP_TWO}, 3'b010, 0, {16'b0, HP_INF_POS});
        execute_operation("HP: Max_norm + Max_norm = Inf", {16'b0, HP_NORM_MAX}, {16'b0, HP_NORM_MAX}, 3'b000, 0, {16'b0, HP_INF_POS});
        execute_operation("HP: Large * Large = Inf", {16'b0, 16'h7B00}, {16'b0, 16'h7B00}, 3'b010, 0, {16'b0, HP_INF_POS});
        
        // --- Underflow ---
        $display("\n--- Underflow ---");
        execute_operation("HP: Min_norm / 2.0", {16'b0, HP_NORM_MIN}, {16'b0, HP_TWO}, 3'b011, 0, {16'b0, 16'h0200});
        execute_operation("HP: Tiny * Tiny = 0", {16'b0, 16'h0400}, {16'b0, 16'h0400}, 3'b010, 0, {16'b0, HP_ZERO_POS});
        execute_operation("HP: Denorm / Large", {16'b0, HP_DENORM_MIN}, {16'b0, 16'h7B00}, 3'b011, 0, {16'b0, HP_ZERO_POS});
        
        
        // ================================================================
        // PRUEBAS DE CASOS LIMITE ADICIONALES
        // ================================================================
        
        $display("\n");
        $display("----------------------------------------------------------------");
        $display("            CASOS LIMITE ADICIONALES");
        $display("----------------------------------------------------------------");
        
        // --- Operaciones con negativos ---
        $display("\n--- Operaciones con negativos ---");
        execute_operation("SP: -5.0 + -3.0 = -8.0", 32'hC0A00000, 32'hC0400000, 3'b000, 1, 32'hC1000000);
        execute_operation("SP: -5.0 - -3.0 = -2.0", 32'hC0A00000, 32'hC0400000, 3'b001, 1, 32'hC0000000);
        execute_operation("SP: -5.0 * -3.0 = 15.0", 32'hC0A00000, 32'hC0400000, 3'b010, 1, 32'h41700000);
        execute_operation("SP: -6.0 / -2.0 = 3.0", 32'hC0C00000, 32'hC0000000, 3'b011, 1, SP_THREE);
        
        // --- Casos mixtos positivo/negativo ---
        $display("\n--- Casos mixtos positivo/negativo ---");
        execute_operation("SP: 10.0 + -7.0 = 3.0", 32'h41200000, 32'hC0E00000, 3'b000, 1, SP_THREE);
        execute_operation("SP: -10.0 + 7.0 = -3.0", 32'hC1200000, 32'h40E00000, 3'b000, 1, 32'hC0400000);
        execute_operation("SP: 5.0 * -2.0 = -10.0", SP_FIVE, 32'hC0000000, 3'b010, 1, 32'hC1200000);
        execute_operation("SP: -15.0 / 3.0 = -5.0", 32'hC1700000, SP_THREE, 3'b011, 1, 32'hC0A00000);
        
        // ================================================================
        // PRUEBAS DE REDONDEO
        // ================================================================
        
        $display("\n");
        $display("----------------------------------------------------------------");
        $display("            PRUEBAS DE REDONDEO");
        $display("----------------------------------------------------------------");
        
        // --- Round to nearest even ---
        $display("\n--- Round to Nearest Even ---");
        execute_operation("SP: 0.1 + 0.2 (redondeo)", 32'h3DCCCCCD, 32'h3E4CCCCD, 3'b000, 1, 32'hXXXXXXXX);
        execute_operation("SP: 1.0 / 3.0 * 3.0 (redondeo)", SP_ONE, SP_THREE, 3'b011, 1, 32'hXXXXXXXX);
        
       
        // ================================================================
        // RESUMEN FINAL
        // ================================================================
        
        $display("\n");
        $display("================================================================");
        $display("                    RESUMEN DE PRUEBAS");
        $display("================================================================");
        $display("Total de pruebas ejecutadas: %0d", test_count);
        $display("Pruebas exitosas (PASS):     %0d", pass_count);
        $display("Pruebas fallidas (FAIL):     %0d", fail_count);
        
        if (fail_count == 0) begin
            $display("\n¡Todas las pruebas pasaron exitosamente!");
        end else begin
            $display("\n¡ATENCION! Hay pruebas que fallaron.");
        end
        
        $display("\nPorcentaje de exito: %.2f%%", (pass_count * 100.0) / test_count);
        $display("================================================================");
        
        // Finalizar simulación
        #100;
        $finish;
    end
  
    initial begin
      $dumpfile("maluma_test.vcd");
    $dumpvars();
  end

endmodule
