`timescale 1ns / 1ns
// =====================================
// Testbench para ALU IEEE-754
// =====================================
module mALUma_tb();

    // Señales de entrada
    reg clk;
    reg rst;
    reg start;
    reg [31:0] op_a, op_b;
    reg [2:0] op_code;
    reg mode_fp;
    reg round_mode;
    
    // Señales de salida
    wire [31:0] result;
    wire valid_out;
    wire [4:0] flags;
    
    // Instancia del módulo mALUma
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
    
    // Generación del reloj
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Dump para visualización (opcional)
    //initial begin
        //$dumpfile("alu_modular_test.vcd");
        //$dumpvars(0, mALUma_tb);
   // end

    // Función para convertir real a IEEE-754 (aproximación)
    function [31:0] real_to_ieee754;
        input real value;
        begin
            real_to_ieee754 = $realtobits(value);
        end
    endfunction

    // Tarea para mostrar resultados de la operación
    task display_result;
        input [31:0] a_val, b_val, res_val;
        input [4:0] flag_val;
        input mode;
        begin
            if (mode) begin // Single precision
                $display("  A     = %h (%.6f)", a_val, $bitstoreal(a_val));
                $display("  B     = %h (%.6f)", b_val, $bitstoreal(b_val));
                $display("  Result= %h (%.6f)", res_val, $bitstoreal(res_val));
            end else begin // Half precision
                $display("  A     = %h (Half)", a_val[15:0]);
                $display("  B     = %h (Half)", b_val[15:0]);
                $display("  Result= %h (Half)", res_val[15:0]);
            end
            
            $display("  Flags = %b", flag_val);
            if (flag_val != 0) begin
                if (flag_val[4]) $display("    - Inexact");
                if (flag_val[3]) $display("    - Invalid Operation");
                if (flag_val[2]) $display("    - Divide by Zero");
                if (flag_val[1]) $display("    - Overflow");
                if (flag_val[0]) $display("    - Underflow");
            end
        end
    endtask
    
    // Tarea para ejecutar operación y esperar resultado
    task execute_operation;
        input [31:0] a_val, b_val;
        input [2:0] op;
        input mode;
        begin
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
            
            display_result(a_val, b_val, result, flags, mode);
        end
    endtask

    // Tarea para verificar las flags
    task check_flags;
        input [31:0] a_val, b_val, res_val;
        input [4:0] flag_val;
        begin
            $display("Comprobando Flags: ");
            // Mostrar flags
            if (flag_val != 0) begin
                if (flag_val[4]) $display("    - Inexacto");
                if (flag_val[3]) $display("    - Operación no válida");
                if (flag_val[2]) $display("    - División por cero");
                if (flag_val[1]) $display("    - Desbordamiento");
                if (flag_val[0]) $display("    - Subdesbordamiento");
            end
        end
    endtask
    
    // Testbench principal
    initial begin
        // Inicialización
        $display("\n=== INICIO DE PRUEBAS - mALUma ===");
        $display("Timestamp: %0t", $time);
        
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
        
        // ====================================
        // PRUEBAS BÁSICAS - SINGLE PRECISION
        // ====================================
        
        // Test 1: Suma simple (2.5 + 1.5 = 4.0)
        execute_operation(32'h3FC00000, 32'h3F800000, 3'b000, 1);
        
        // Test 2: Resta (5.75 - 2.25 = 3.5)
        execute_operation(32'h40100000, 32'h3F900000, 3'b001, 1);
        
        // Test 3: Multiplicación (3.0 * 2.0 = 6.0)
        execute_operation(32'h40000000, 32'h40000000, 3'b010, 1);
        
        // Test 4: División (9.0 / 3.0 = 3.0)
        execute_operation(32'h40400000, 32'h40400000, 3'b011, 1);
       
        // Test 5: Suma con negativos (10.0 + (-2.0) = 8.0)
        execute_operation(32'h40200000, 32'hC0000000, 3'b000, 1);
        
        // Test 6: División negativa ((-4.0) / 2.0 = -2.0)
        execute_operation(32'hC0000000, 32'h40000000, 3'b011, 1);
        
        // ====================================
        // CASOS ESPECIALES - NaN
        // ====================================
        
        // Test 7: NaN + número = NaN
        execute_operation(32'h7FC00000, 32'h40000000, 3'b000, 1);
        
        // Test 8: 0/0 = NaN
        execute_operation(32'h00000000, 32'h00000000, 3'b011, 1);
        
        // Test 9: inf - inf = NaN
        execute_operation(32'h7F800000, 32'h7F800000, 3'b001, 1);
        
        // Test 10: inf * 0 = NaN
        execute_operation(32'h7F800000, 32'h00000000, 3'b010, 1);
        
        // ====================================
        // CASOS ESPECIALES - INFINITO
        // ====================================
        
        // Test 11: División por cero (5.0/0 = inf)1
        execute_operation(32'h40000000, 32'h00000000, 3'b011, 1);
        
        // Test 12: inf + número = inf
        execute_operation(32'h7F800000, 32'h40000000, 3'b000, 1);
        
        // Test 13: inf * número = inf
        execute_operation(32'h7F800000, 32'h40000000, 3'b010, 1);
        
        // ====================================1
        // CEROS CON SIGNO
        // ====================================
        
        // Test 14: +0 + -0 = +0
        execute_operation(32'h00000000, 32'h80000000, 3'b000, 1);
        
        // Test 15: -0 * 2.0 = -0
        execute_operation(32'h80000000, 32'h40000000, 3'b010, 1);
        
        // ====================================
        // NÚMEROS DENORMALIZADOS
        // ====================================
        
        // Test 16: Número denormal muy pequeño
        execute_operation(32'h00000001, 32'h00000001, 3'b000, 1);
        
        // Test 17: Denormal * número normal
        execute_operation(32'h00000001, 32'h40000000, 3'b010, 1);
        
        // Test 18: Denormal + número normal
        execute_operation(32'h00000001, 32'h40400000, 3'b000, 1);
        
        $display("=== FIN DE PRUEBAS ===");
        $finish;
    end
endmodule
