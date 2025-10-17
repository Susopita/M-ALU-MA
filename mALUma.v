// ==============================
// ALU Punto Flotante IEEE-754 
// ==============================

// ==============================
// Módulo Principal de la ALU
// ==============================
module mALUma(
    input clk,
    input rst,
    input start,
    input [31:0] op_a,
    input [31:0] op_b,
    input [2:0] op_code,      // 000:ADD, 001:SUB, 010:MUL, 011:DIV
    input mode_fp,             // 0 = half (16 bits), 1 = single (32 bits)
    input round_mode,          // 0 = round to nearest even
    output reg [31:0] result,
    output reg valid_out,
    output reg [4:0] flags     // [4:inexact, 3:invalid, 2:div_by_zero, 1:overflow, 0:underflow]
);

    // Estados de la FSM
    localparam IDLE = 2'b00;
    localparam COMPUTE = 2'b01;
    localparam OUTPUT = 2'b10;
    
    reg [1:0] state, next_state;
    
    // Señales para single precision (32 bits)
    wire [31:0] result_add_32, result_sub_32, result_mul_32, result_div_32;
    wire [4:0] flags_add_32, flags_sub_32, flags_mul_32, flags_div_32;
    
    // Señales para half precision (16 bits)
    wire [15:0] result_add_16, result_sub_16, result_mul_16, result_div_16;
    wire [4:0] flags_add_16, flags_sub_16, flags_mul_16, flags_div_16;
    
    // Multiplexores para resultados
    reg [31:0] result_32_mux;
    reg [4:0] flags_32_mux;
    reg [15:0] result_16_mux;
    reg [4:0] flags_16_mux;
    
    // =====================================
    // Instancias para Single Precision (32 bits)
    // =====================================
    
    fp32_add add_32(
        .a(op_a),
        .b(op_b),
        .round_mode(round_mode),
        .result(result_add_32),
        .flags(flags_add_32)
    );
    
    fp32_sub sub_32(
        .a(op_a),
        .b(op_b),
        .round_mode(round_mode),
        .result(result_sub_32),
        .flags(flags_sub_32)
    );
    
    fp32_mul mul_32(
        .a(op_a),
        .b(op_b),
        .round_mode(round_mode),
        .result(result_mul_32),
        .flags(flags_mul_32)
    );
    
    fp32_div div_32(
        .a(op_a),
        .b(op_b),
        .round_mode(round_mode),
        .result(result_div_32),
        .flags(flags_div_32)
    );
    
    // =====================================
    // Instancias para Half Precision (16 bits)
    // =====================================
    
    fp16_add add_16(
        .a(op_a[15:0]),
        .b(op_b[15:0]),
        .round_mode(round_mode),
        .result(result_add_16),
        .flags(flags_add_16)
    );
    
    fp16_sub sub_16(
        .a(op_a[15:0]),
        .b(op_b[15:0]),
        .round_mode(round_mode),
        .result(result_sub_16),
        .flags(flags_sub_16)
    );
    
    fp16_mul mul_16(
        .a(op_a[15:0]),
        .b(op_b[15:0]),
        .round_mode(round_mode),
        .result(result_mul_16),
        .flags(flags_mul_16)
    );
    
    fp16_div div_16(
        .a(op_a[15:0]),
        .b(op_b[15:0]),
        .round_mode(round_mode),
        .result(result_div_16),
        .flags(flags_div_16)
    );
    
    // Multiplexor de resultados según operación
    always @(*) begin
        // Single precision
        case (op_code[1:0])
            2'b00: begin  // ADD
                result_32_mux = result_add_32;
                flags_32_mux = flags_add_32;
            end
            2'b01: begin  // SUB
                result_32_mux = result_sub_32;
                flags_32_mux = flags_sub_32;
            end
            2'b10: begin  // MUL
                result_32_mux = result_mul_32;
                flags_32_mux = flags_mul_32;
            end
            2'b11: begin  // DIV
                result_32_mux = result_div_32;
                flags_32_mux = flags_div_32;
            end
        endcase
        
        // Half precision
        case (op_code[1:0])
            2'b00: begin  // ADD
                result_16_mux = result_add_16;
                flags_16_mux = flags_add_16;
            end
            2'b01: begin  // SUB
                result_16_mux = result_sub_16;
                flags_16_mux = flags_sub_16;
            end
            2'b10: begin  // MUL
                result_16_mux = result_mul_16;
                flags_16_mux = flags_mul_16;
            end
            2'b11: begin  // DIV
                result_16_mux = result_div_16;
                flags_16_mux = flags_div_16;
            end
        endcase
    end
    
    // FSM Control
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            valid_out <= 1'b0;
        end else begin
            state <= next_state;
        end
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) next_state = COMPUTE;
            end
            COMPUTE: begin
                next_state = OUTPUT;
            end
            OUTPUT: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Registro de salida
    always @(posedge clk) begin
        if (rst) begin
            result <= 32'b0;
            flags <= 5'b0;
            valid_out <= 1'b0;
        end else begin
            case (state)
                COMPUTE: begin
                    if (mode_fp) begin // Single precision
                        result <= result_32_mux;
                        flags <= flags_32_mux;
                    end else begin // Half precision
                        result <= {16'b0, result_16_mux};
                        flags <= flags_16_mux;
                    end
                    valid_out <= 1'b1;
                end
                IDLE: begin
                    valid_out <= 1'b0;
                end
            endcase
        end
    end

endmodule

// =====================================
// Módulo Sumador Single Precision (32 bits)
// =====================================
module fp32_add(
    input [31:0] a,
    input [31:0] b,
    input round_mode,
    output [31:0] result,
    output [4:0] flags
);
    
    // Instancia del módulo de suma/resta con add_sub = 0
    fp32_add_sub add_sub_inst(
        .a(a),
        .b(b),
        .add_sub(1'b0),  // 0 = suma
        .round_mode(round_mode),
        .result(result),
        .flags(flags)
    );
    
endmodule

// =====================================
// Módulo Restador Single Precision (32 bits)
// =====================================
module fp32_sub(
    input [31:0] a,
    input [31:0] b,
    input round_mode,
    output [31:0] result,
    output [4:0] flags
);
    
    // Instancia del módulo de suma/resta con add_sub = 1
    fp32_add_sub add_sub_inst(
        .a(a),
        .b(b),
        .add_sub(1'b1),  // 1 = resta
        .round_mode(round_mode),
        .result(result),
        .flags(flags)
    );
    
endmodule

// =====================================
// Módulo Suma/Resta Single Precision (32 bits)
// =====================================
module fp32_add_sub(
    input [31:0] a,
    input [31:0] b,
    input add_sub,      // 0 = add, 1 = sub
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[31];
    wire sign_b_eff = b[31] ^ add_sub;  // Invertir signo para resta
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] mant_a = a[22:0];
    wire [22:0] mant_b = b[22:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 8'hFF) && (mant_a != 0);
    wire b_is_nan = (exp_b == 8'hFF) && (mant_b != 0);
    wire a_is_inf = (exp_a == 8'hFF) && (mant_a == 0);
    wire b_is_inf = (exp_b == 8'hFF) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [24:0] mant_a_norm, mant_b_norm;
    reg [7:0] exp_diff;
    reg [26:0] mant_aligned_a, mant_aligned_b;
    reg [27:0] mant_sum;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    integer leading_zeros;
    
    always @(*) begin
        flags = 5'b0;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 32'h7FC00000; // QNaN
            flags[3] = 1; // Operación inválida
        end
        // Manejo de infinitos
        else if (a_is_inf || b_is_inf) begin
            if (a_is_inf && b_is_inf && (sign_a != sign_b_eff)) begin
                // inf - inf = NaN
                result = 32'h7FC00000;
                flags[3] = 1; // Invalido
            end else begin
                // inf + x = inf, x + inf = inf
                sign_result = a_is_inf ? sign_a : sign_b_eff;
                result = {sign_result, 8'hFF, 23'b0};
            end
        end
        // Manejo de ceros
        else if (a_is_zero && b_is_zero) begin
            sign_result = sign_a & sign_b_eff; // +0 + -0 = +0
            result = {sign_result, 31'b0};
        end
        else if (a_is_zero) begin
            result = {sign_b_eff, b[30:0]};
        end
        else if (b_is_zero) begin
            result = a;
        end
        // Operación normal
        else begin
            // Agregar bit implícito (1 para normales, 0 para denormales)
            mant_a_norm = a_is_denorm ? {2'b00, mant_a} : {2'b01, mant_a};
            mant_b_norm = b_is_denorm ? {2'b00, mant_b} : {2'b01, mant_b};
            
            // Alinear exponentes
            if (exp_a > exp_b) begin
                exp_diff = exp_a - exp_b;
                exp_result = exp_a;
                mant_aligned_a = {2'b0, mant_a_norm};
                mant_aligned_b = {2'b0, mant_b_norm} >> exp_diff;
            end else begin
                exp_diff = exp_b - exp_a;
                exp_result = exp_b;
                mant_aligned_a = {2'b0, mant_a_norm} >> exp_diff;
                mant_aligned_b = {2'b0, mant_b_norm};
            end
            
            // Suma o resta según los signos
            if (sign_a == sign_b_eff) begin
                // Suma efectiva
                mant_sum = mant_aligned_a + mant_aligned_b;
                sign_result = sign_a;
            end else begin
                // Resta efectiva
                if (mant_aligned_a >= mant_aligned_b) begin
                    mant_sum = mant_aligned_a - mant_aligned_b;
                    sign_result = sign_a;
                end else begin
                    mant_sum = mant_aligned_b - mant_aligned_a;
                    sign_result = sign_b_eff;
                end
            end
            
            // Normalización
            if (mant_sum[26]) begin
                // Overflow de mantisa - desplazar a la derecha
                exp_result = exp_result + 1;
                mant_result = mant_sum[26:4] + (round_mode == 0 && mant_sum[3]);
                
                if (exp_result >= 255) begin
                    // Overflow del exponente
                    flags[1] = 1;
                    result = {sign_result, 8'hFF, 23'b0}; // Infinito
                end else begin
                    result = {sign_result, exp_result, mant_result};
                end
            end else if (mant_sum[25]) begin
                // Ya normalizado
                mant_result = mant_sum[25:3] + (round_mode == 0 && mant_sum[2]);
                result = {sign_result, exp_result, mant_result};
            end else if (mant_sum == 0) begin
                // Resultado es cero
                result = {sign_result, 31'b0};
            end else begin
                // Necesita normalización a la izquierda
                leading_zeros = 0;
                for (integer i = 24; i >= 0; i = i - 1) begin
                    if (mant_sum[i] == 1 && leading_zeros == 0) begin
                        leading_zeros = 25 - i;
                    end
                end
                
                if (leading_zeros > exp_result) begin
                    // Underflow - resultado denormalizado o cero
                    if (exp_result == 0) begin
                        // Ya es denormal
                        mant_result = mant_sum[24:2];
                    end else begin
                        // Se convierte en denormal
                        mant_sum = mant_sum << (exp_result - 1);
                        mant_result = mant_sum[24:2];
                        exp_result = 0;
                    end
                    flags[0] = 1; // Underflow
                    result = {sign_result, exp_result, mant_result};
                end else begin
                    // Normalización normal
                    exp_result = exp_result - leading_zeros;
                    mant_sum = mant_sum << leading_zeros;
                    mant_result = mant_sum[25:3] + (round_mode == 0 && mant_sum[2]);
                    result = {sign_result, exp_result, mant_result};
                end
            end
            
            // Flag de inexacto
            if (mant_sum[2:0] != 0) flags[4] = 1;
        end
    end
    
endmodule

// =====================================
// Módulo Multiplicador Single Precision (32 bits)
// =====================================
module fp32_mul(
    input [31:0] a,
    input [31:0] b,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] mant_a = a[22:0];
    wire [22:0] mant_b = b[22:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 8'hFF) && (mant_a != 0);
    wire b_is_nan = (exp_b == 8'hFF) && (mant_b != 0);
    wire a_is_inf = (exp_a == 8'hFF) && (mant_a == 0);
    wire b_is_inf = (exp_b == 8'hFF) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [47:0] mant_product;
    reg [8:0] exp_sum;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        sign_result = sign_a ^ sign_b;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 32'h7FC00000;
            flags[3] = 1;
        end
        // 0 * inf = NaN
        else if ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero)) begin
            result = 32'h7FC00000;
            flags[3] = 1;
        end
        // Infinito * x = infinito
        else if (a_is_inf || b_is_inf) begin
            result = {sign_result, 8'hFF, 23'b0};
        end
        // 0 * x = 0
        else if (a_is_zero || b_is_zero) begin
            result = {sign_result, 31'b0};
        end
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // Multiplicar mantisas
            mant_product = mant_a_norm * mant_b_norm;
            
            // Calcular exponente
            exp_sum = exp_a + exp_b;
            
            // Ajustar bias
            if (!a_is_denorm && !b_is_denorm) begin
                exp_sum = exp_sum - 127;
            end else if (a_is_denorm && b_is_denorm) begin
                exp_sum = exp_sum + 1;
            end
            
            // Normalizar resultado
            if (mant_product[47]) begin
                // Producto normalizado con bit en posición 47
                exp_result = exp_sum + 1;
                mant_result = mant_product[46:24] + (round_mode == 0 && mant_product[23]);
            end else begin
                // Producto normalizado con bit en posición 46
                exp_result = exp_sum;
                mant_result = mant_product[45:23] + (round_mode == 0 && mant_product[22]);
            end
            
            // Verificar overflow/underflow
            if (exp_sum >= 255 || exp_result >= 255) begin
                flags[1] = 1; // Overflow
                result = {sign_result, 8'hFF, 23'b0};
            end else if (exp_sum <= 0 || exp_result == 0) begin
                flags[0] = 1; // Underflow
                result = {sign_result, 8'h00, 23'b0};
            end else begin
                result = {sign_result, exp_result, mant_result};
            end
            
            // Flag inexacto
            if (mant_product[22:0] != 0) flags[4] = 1;
        end
    end
    
endmodule

// =====================================
// Módulo Divisor Single Precision (32 bits)
// =====================================
module fp32_div(
    input [31:0] a,
    input [31:0] b,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] mant_a = a[22:0];
    wire [22:0] mant_b = b[22:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 8'hFF) && (mant_a != 0);
    wire b_is_nan = (exp_b == 8'hFF) && (mant_b != 0);
    wire a_is_inf = (exp_a == 8'hFF) && (mant_a == 0);
    wire b_is_inf = (exp_b == 8'hFF) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [47:0] mant_quotient;
    reg [8:0] exp_diff;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        sign_result = sign_a ^ sign_b;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 32'h7FC00000;
            flags[3] = 1;
        end
        // 0/0 = NaN, inf/inf = NaN
        else if ((a_is_zero && b_is_zero) || (a_is_inf && b_is_inf)) begin
            result = 32'h7FC00000;
            flags[3] = 1;
        end
        // x/0 = inf (división por cero)
        else if (b_is_zero) begin
            result = {sign_result, 8'hFF, 23'b0};
            flags[2] = 1; // Divide by zero
        end
        // inf/x = inf
        else if (a_is_inf) begin
            result = {sign_result, 8'hFF, 23'b0};
        end
        // x/inf = 0
        else if (b_is_inf) begin
            result = {sign_result, 31'b0};
        end
        // 0/x = 0
        else if (a_is_zero) begin
            result = {sign_result, 31'b0};
        end
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // División de mantisas (con precisión extendida)
            mant_quotient = ({mant_a_norm, 24'b0}) / mant_b_norm;
            
            // Calcular exponente
            exp_diff = exp_a - exp_b + 127;
            
            // Ajustar para denormales
            if (a_is_denorm) exp_diff = exp_diff - 1;
            if (b_is_denorm) exp_diff = exp_diff + 1;
            
            // Normalizar resultado
            if (mant_quotient[47]) begin
                exp_result = exp_diff + 1;
                mant_result = mant_quotient[46:24] + (round_mode == 0 && mant_quotient[23]);
            end else if (mant_quotient[46]) begin
                exp_result = exp_diff;
                mant_result = mant_quotient[45:23] + (round_mode == 0 && mant_quotient[22]);
            end else begin
                exp_result = exp_diff - 1;
                mant_result = mant_quotient[44:22] + (round_mode == 0 && mant_quotient[21]);
            end
            
            // Verificar overflow/underflow
            if (exp_diff >= 255 || exp_result >= 255) begin
                flags[1] = 1; // Overflow
                result = {sign_result, 8'hFF, 23'b0};
            end else if (exp_diff <= 0 || exp_result == 0) begin
                flags[0] = 1; // Underflow  
                result = {sign_result, 8'h00, 23'b0};
            end else begin
                result = {sign_result, exp_result, mant_result};
            end
            
            // Flag inexacto
            if (mant_quotient[22:0] != 0) flags[4] = 1;
        end
    end
    
endmodule

// =====================================
// Módulos para Half Precision (16 bits)
// =====================================

// Módulo Sumador Half Precision
module fp16_add(
    input [15:0] a,
    input [15:0] b,
    input round_mode,
    output [15:0] result,
    output [4:0] flags
);
    
    fp16_add_sub add_sub_inst(
        .a(a),
        .b(b),
        .add_sub(1'b0),
        .round_mode(round_mode),
        .result(result),
        .flags(flags)
    );
    
endmodule

// Módulo Restador Half Precision
module fp16_sub(
    input [15:0] a,
    input [15:0] b,
    input round_mode,
    output [15:0] result,
    output [4:0] flags
);
    
    fp16_add_sub add_sub_inst(
        .a(a),
        .b(b),
        .add_sub(1'b1),
        .round_mode(round_mode),
        .result(result),
        .flags(flags)
    );
    
endmodule

// Módulo Suma/Resta Half Precision
module fp16_add_sub(
    input [15:0] a,
    input [15:0] b,
    input add_sub,
    input round_mode,
    output reg [15:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[15];
    wire sign_b_eff = b[15] ^ add_sub;
    wire [4:0] exp_a = a[14:10];
    wire [4:0] exp_b = b[14:10];
    wire [9:0] mant_a = a[9:0];
    wire [9:0] mant_b = b[9:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 5'h1F) && (mant_a != 0);
    wire b_is_nan = (exp_b == 5'h1F) && (mant_b != 0);
    wire a_is_inf = (exp_a == 5'h1F) && (mant_a == 0);
    wire b_is_inf = (exp_b == 5'h1F) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [11:0] mant_a_norm, mant_b_norm;
    reg [4:0] exp_diff;
    reg [13:0] mant_aligned_a, mant_aligned_b;
    reg [14:0] mant_sum;
    reg sign_result;
    reg [4:0] exp_result;
    reg [9:0] mant_result;
    integer leading_zeros;
    
    always @(*) begin
        flags = 5'b0;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 16'h7E00; // QNaN para half
            flags[3] = 1;
        end
        // Manejo de infinitos
        else if (a_is_inf || b_is_inf) begin
            if (a_is_inf && b_is_inf && (sign_a != sign_b_eff)) begin
                result = 16'h7E00; // inf - inf = NaN
                flags[3] = 1;
            end else begin
                sign_result = a_is_inf ? sign_a : sign_b_eff;
                result = {sign_result, 5'h1F, 10'b0};
            end
        end
        // Manejo de ceros
        else if (a_is_zero && b_is_zero) begin
            sign_result = sign_a & sign_b_eff;
            result = {sign_result, 15'b0};
        end
        else if (a_is_zero) begin
            result = {sign_b_eff, b[14:0]};
        end
        else if (b_is_zero) begin
            result = a;
        end
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {2'b00, mant_a} : {2'b01, mant_a};
            mant_b_norm = b_is_denorm ? {2'b00, mant_b} : {2'b01, mant_b};
            
            // Alinear exponentes
            if (exp_a > exp_b) begin
                exp_diff = exp_a - exp_b;
                exp_result = exp_a;
                mant_aligned_a = {2'b0, mant_a_norm};
                mant_aligned_b = {2'b0, mant_b_norm} >> exp_diff;
            end else begin
                exp_diff = exp_b - exp_a;
                exp_result = exp_b;
                mant_aligned_a = {2'b0, mant_a_norm} >> exp_diff;
                mant_aligned_b = {2'b0, mant_b_norm};
            end
            
            // Suma o resta
            if (sign_a == sign_b_eff) begin
                mant_sum = mant_aligned_a + mant_aligned_b;
                sign_result = sign_a;
            end else begin
                if (mant_aligned_a >= mant_aligned_b) begin
                    mant_sum = mant_aligned_a - mant_aligned_b;
                    sign_result = sign_a;
                end else begin
                    mant_sum = mant_aligned_b - mant_aligned_a;
                    sign_result = sign_b_eff;
                end
            end
            
            // Normalización
            if (mant_sum[12]) begin
                exp_result = exp_result + 1;
                mant_result = mant_sum[12:3] + (round_mode == 0 && mant_sum[2]);
                
                if (exp_result >= 31) begin
                    flags[1] = 1; // Overflow
                    result = {sign_result, 5'h1F, 10'b0};
                end else begin
                    result = {sign_result, exp_result, mant_result};
                end
            end else if (mant_sum[11]) begin
                mant_result = mant_sum[11:2] + (round_mode == 0 && mant_sum[1]);
                result = {sign_result, exp_result, mant_result};
            end else if (mant_sum == 0) begin
                result = {sign_result, 15'b0};
            end else begin
                // Normalización a la izquierda
                leading_zeros = 0;
                for (integer i = 10; i >= 0; i = i - 1) begin
                    if (mant_sum[i] == 1 && leading_zeros == 0) begin
                        leading_zeros = 11 - i;
                    end
                end
                
                if (leading_zeros > exp_result) begin
                    flags[0] = 1; // Underflow
                    result = {sign_result, 5'h00, 10'b0};
                end else begin
                    exp_result = exp_result - leading_zeros;
                    mant_sum = mant_sum << leading_zeros;
                    mant_result = mant_sum[11:2];
                    result = {sign_result, exp_result, mant_result};
                end
            end
            
            if (mant_sum[1:0] != 0) flags[4] = 1; // Inexact
        end
    end
    
endmodule

// Módulo Multiplicador Half Precision
module fp16_mul(
    input [15:0] a,
    input [15:0] b,
    input round_mode,
    output reg [15:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[15];
    wire sign_b = b[15];
    wire [4:0] exp_a = a[14:10];
    wire [4:0] exp_b = b[14:10];
    wire [9:0] mant_a = a[9:0];
    wire [9:0] mant_b = b[9:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 5'h1F) && (mant_a != 0);
    wire b_is_nan = (exp_b == 5'h1F) && (mant_b != 0);
    wire a_is_inf = (exp_a == 5'h1F) && (mant_a == 0);
    wire b_is_inf = (exp_b == 5'h1F) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [21:0] mant_product;
    reg [5:0] exp_sum;
    reg sign_result;
    reg [4:0] exp_result;
    reg [9:0] mant_result;
    reg [10:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        sign_result = sign_a ^ sign_b;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 16'h7E00;
            flags[3] = 1;
        end
        // 0 * inf = NaN
        else if ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero)) begin
            result = 16'h7E00;
            flags[3] = 1;
        end
        // Infinito
        else if (a_is_inf || b_is_inf) begin
            result = {sign_result, 5'h1F, 10'b0};
        end
        // Cero
        else if (a_is_zero || b_is_zero) begin
            result = {sign_result, 15'b0};
        end
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // Multiplicar mantisas
            mant_product = mant_a_norm * mant_b_norm;
            
            // Calcular exponente
            exp_sum = exp_a + exp_b;
            
            // Ajustar bias (15 para half)
            if (!a_is_denorm && !b_is_denorm) begin
                exp_sum = exp_sum - 15;
            end else if (a_is_denorm && b_is_denorm) begin
                exp_sum = exp_sum + 1;
            end
            
            // Normalizar
            if (mant_product[21]) begin
                exp_result = exp_sum + 1;
                mant_result = mant_product[20:11] + (round_mode == 0 && mant_product[10]);
            end else begin
                exp_result = exp_sum;
                mant_result = mant_product[19:10] + (round_mode == 0 && mant_product[9]);
            end
            
            // Verificar overflow/underflow
            if (exp_sum >= 31 || exp_result >= 31) begin
                flags[1] = 1; // Overflow
                result = {sign_result, 5'h1F, 10'b0};
            end else if (exp_sum <= 0 || exp_result == 0) begin
                flags[0] = 1; // Underflow
                result = {sign_result, 5'h00, 10'b0};
            end else begin
                result = {sign_result, exp_result, mant_result};
            end
            
            if (mant_product[9:0] != 0) flags[4] = 1; // Inexact
        end
    end
    
endmodule

// Módulo Divisor Half Precision
module fp16_div(
    input [15:0] a,
    input [15:0] b,
    input round_mode,
    output reg [15:0] result,
    output reg [4:0] flags
);
    
    // Descomponer operandos
    wire sign_a = a[15];
    wire sign_b = b[15];
    wire [4:0] exp_a = a[14:10];
    wire [4:0] exp_b = b[14:10];
    wire [9:0] mant_a = a[9:0];
    wire [9:0] mant_b = b[9:0];
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == 5'h1F) && (mant_a != 0);
    wire b_is_nan = (exp_b == 5'h1F) && (mant_b != 0);
    wire a_is_inf = (exp_a == 5'h1F) && (mant_a == 0);
    wire b_is_inf = (exp_b == 5'h1F) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables internas
    reg [21:0] mant_quotient;
    reg [5:0] exp_diff;
    reg sign_result;
    reg [4:0] exp_result;
    reg [9:0] mant_result;
    reg [10:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        sign_result = sign_a ^ sign_b;
        
        // Manejo de NaN
        if (a_is_nan || b_is_nan) begin
            result = 16'h7E00;
            flags[3] = 1;
        end
        // 0/0 = NaN, inf/inf = NaN
        else if ((a_is_zero && b_is_zero) || (a_is_inf && b_is_inf)) begin
            result = 16'h7E00;
            flags[3] = 1;
        end
        // División por cero
        else if (b_is_zero) begin
            result = {sign_result, 5'h1F, 10'b0};
            flags[2] = 1;
        end
        // inf/x = inf
        else if (a_is_inf) begin
            result = {sign_result, 5'h1F, 10'b0};
        end
        // x/inf = 0
        else if (b_is_inf) begin
            result = {sign_result, 15'b0};
        end
        // 0/x = 0
        else if (a_is_zero) begin
            result = {sign_result, 15'b0};
        end
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // División de mantisas
            mant_quotient = ({mant_a_norm, 11'b0}) / mant_b_norm;
            
            // Calcular exponente
            exp_diff = exp_a - exp_b + 15;
            
            // Ajustar para denormales
            if (a_is_denorm) exp_diff = exp_diff - 1;
            if (b_is_denorm) exp_diff = exp_diff + 1;
            
            // Normalizar
            if (mant_quotient[21]) begin
                exp_result = exp_diff + 1;
                mant_result = mant_quotient[20:11] + (round_mode == 0 && mant_quotient[10]);
            end else if (mant_quotient[20]) begin
                exp_result = exp_diff;
                mant_result = mant_quotient[19:10] + (round_mode == 0 && mant_quotient[9]);
            end else begin
                exp_result = exp_diff - 1;
                mant_result = mant_quotient[18:9] + (round_mode == 0 && mant_quotient[8]);
            end
            
            // Verificar overflow/underflow
            if (exp_diff >= 31 || exp_result >= 31) begin
                flags[1] = 1; // Overflow
                result = {sign_result, 5'h1F, 10'b0};
            end else if (exp_diff <= 0 || exp_result == 0) begin
                flags[0] = 1; // Underflow
                result = {sign_result, 5'h00, 10'b0};
            end else begin
                result = {sign_result, exp_result, mant_result};
            end
            
            if (mant_quotient[9:0] != 0) flags[4] = 1; // Inexact
        end
    end
    
endmodule

// =====================================
// Módulo de Utilidades Compartidas
// =====================================
module fp_utils(
    input [31:0] value_32,
    input [15:0] value_16,
    input mode,  // 0 = half, 1 = single
    output is_nan,
    output is_inf,
    output is_zero,
    output is_denorm,
    output sign
);
    
    // Para single precision
    wire [7:0] exp_32 = value_32[30:23];
    wire [22:0] mant_32 = value_32[22:0];
    wire sign_32 = value_32[31];
    
    wire nan_32 = (exp_32 == 8'hFF) && (mant_32 != 0);
    wire inf_32 = (exp_32 == 8'hFF) && (mant_32 == 0);
    wire zero_32 = (exp_32 == 0) && (mant_32 == 0);
    wire denorm_32 = (exp_32 == 0) && (mant_32 != 0);
    
    // Para half precision
    wire [4:0] exp_16 = value_16[14:10];
    wire [9:0] mant_16 = value_16[9:0];
    wire sign_16 = value_16[15];
    
    wire nan_16 = (exp_16 == 5'h1F) && (mant_16 != 0);
    wire inf_16 = (exp_16 == 5'h1F) && (mant_16 == 0);
    wire zero_16 = (exp_16 == 0) && (mant_16 == 0);
    wire denorm_16 = (exp_16 == 0) && (mant_16 != 0);
    
    // Multiplexar según el modo
    assign is_nan = mode ? nan_32 : nan_16;
    assign is_inf = mode ? inf_32 : inf_16;
    assign is_zero = mode ? zero_32 : zero_16;
    assign is_denorm = mode ? denorm_32 : denorm_16;
    assign sign = mode ? sign_32 : sign_16;
    
endmodule