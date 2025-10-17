// Code your design here
// ==============================
// ALU Punto Flotante IEEE-754 
// Soporte Single (32-bit) y Half (16-bit) precision
// ==============================

// ==============================
// Módulo Principal de la ALU
// ==============================
module mALUma(
    input clk,                  // Reloj del sistema
    input rst,                  // Reset (activo en alto)
    input start,                // Señal para iniciar operación
    input [31:0] op_a,          // Operando A
    input [31:0] op_b,          // Operando B
    input [2:0] op_code,        // Código de operación: 000=ADD, 001=SUB, 010=MUL, 011=DIV
    input mode_fp,              // Modo: 0=half(16-bit), 1=single(32-bit)
    input round_mode,           // Modo de redondeo: 0=nearest even
    output reg [31:0] result,   // Resultado de la operación
    output reg valid_out,       // Indica que el resultado es válido
    output reg [4:0] flags      // Flags: [4:inexact, 3:invalid, 2:div_by_zero, 1:overflow, 0:underflow]
);

    // FSM
    // Estado IDLE: Esperando que start=1
    // Estado COMPUTE: Realizando cálculo y presentando resultado
    
    parameter IDLE    = 1'b0;
    parameter COMPUTE = 1'b1;
    
    reg state, next_state;
    
    // ==========================================
    // Señales de resultados de cada operación
    // ==========================================
    wire [31:0] result_add, result_sub, result_mul, result_div;
    wire [4:0] flags_add, flags_sub, flags_mul, flags_div;
    
    // Señal para seleccionar el resultado según op_code
    reg [31:0] result_selected;
    reg [4:0] flags_selected;
    
    // ==========================================
    // Instanciar los 4 módulos de operaciones
    // Cada uno maneja tanto single como half precision
    // ==========================================
    
    fp_add_sub add_module(
        .a(op_a),
        .b(op_b),
        .add_sub(1'b0),           // 0 = suma
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result_add),
        .flags(flags_add)
    );
    
    fp_add_sub sub_module(
        .a(op_a),
        .b(op_b),
        .add_sub(1'b1),           // 1 = resta
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result_sub),
        .flags(flags_sub)
    );
    
    fp_mul mul_module(
        .a(op_a),
        .b(op_b),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result_mul),
        .flags(flags_mul)
    );
    
    fp_div div_module(
        .a(op_a),
        .b(op_b),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result_div),
        .flags(flags_div)
    );
    
    // ==========================================
    // MULTIPLEXOR: Seleccionar resultado según operación
    // ==========================================
    always @(*) begin
        case (op_code[1:0])
            2'b00: begin  // ADD
                result_selected = result_add;
                flags_selected = flags_add;
            end
            2'b01: begin  // SUB
                result_selected = result_sub;
                flags_selected = flags_sub;
            end
            2'b10: begin  // MUL
                result_selected = result_mul;
                flags_selected = flags_mul;
            end
            2'b11: begin  // DIV
                result_selected = result_div;
                flags_selected = flags_div;
            end
        endcase
    end
    
    // ==========================================
    // FSM - Lógica de transición entre estados
    // ==========================================
    
    // Registro de estado (secuencial)
    always @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // Lógica del siguiente estado (combinacional)
    always @(*) begin
        case (state)
            IDLE: begin
                if (start)
                    next_state = COMPUTE;  // Si start=1, ir a COMPUTE
                else
                    next_state = IDLE;     // Sino, quedarse en IDLE
            end
            
            COMPUTE: begin
                next_state = IDLE;         // Después de computar, volver a IDLE
            end
            
            default: 
                next_state = IDLE;
        endcase
    end
    
    // ====================
    // Lógica de salida 
  	// ====================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset: Limpiar todas las salidas
            result <= 32'b0;
            flags <= 5'b0;
            valid_out <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // En IDLE, no hay resultado válido
                    valid_out <= 1'b0;
                end
                
                COMPUTE: begin
                    // En COMPUTE, guardar resultado y activar valid_out
                    result <= result_selected;
                    flags <= flags_selected;
                    valid_out <= 1'b1;
                end
            endcase
        end
    end

endmodule

// ==========================================
// Módulo de Suma/Resta
// Maneja tanto single (32-bit) como half (16-bit)
// ==========================================
module fp_add_sub(
    input [31:0] a,
    input [31:0] b,
    input add_sub,          // 0=suma, 1=resta
    input mode_fp,          // 0=half, 1=single
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Extraer campos según el modo
    wire sign_a, sign_b_eff;
    wire [7:0] exp_a, exp_b;
    wire [22:0] mant_a, mant_b;
    
    // Para single precision: usar bits completos
    // Para half precision: expandir a formato interno
    assign sign_a = mode_fp ? a[31] : a[15];
    assign sign_b_eff = mode_fp ? (b[31] ^ add_sub) : (b[15] ^ add_sub);  // Invertir signo si es resta
    assign exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    assign exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    assign mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};  // Expandir mantisa de half
    assign mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    // Constantes según el modo
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    // Variables para el cálculo
    reg [24:0] mant_a_norm, mant_b_norm;
    reg [7:0] exp_diff;
    reg [26:0] mant_aligned_a, mant_aligned_b;
    reg [27:0] mant_sum;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    integer leading_zeros, i;
    
    always @(*) begin
        // Inicializar
        flags = 5'b0;
        result = 32'b0;
        
        // ==========================================
        // Casos especiales
        // ==========================================
        
        // Caso NaN
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;  // Invalid operation
        end
        
        // Caso Inf - Inf = NaN
        else if (a_is_inf && b_is_inf && (sign_a != sign_b_eff)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        
        // Caso Inf + x = Inf
        else if (a_is_inf || b_is_inf) begin
            sign_result = a_is_inf ? sign_a : sign_b_eff;
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        
        // Caso 0 + 0
        else if (a_is_zero && b_is_zero) begin
            sign_result = sign_a & sign_b_eff;
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        
        // Caso a=0, devolver b
        else if (a_is_zero) begin
            result = mode_fp ? {sign_b_eff, b[30:0]} : {16'b0, sign_b_eff, b[14:0]};
        end
        
        // Caso b=0, devolver a
        else if (b_is_zero) begin
            result = mode_fp ? a : {16'b0, a[15:0]};
        end
        
        // ==========================================
        // Operación normal
        // ==========================================
        else begin
            // Agregar bit implícito (1 para normales, 0 para denormales)
            mant_a_norm = a_is_denorm ? {2'b00, mant_a} : {2'b01, mant_a};
            mant_b_norm = b_is_denorm ? {2'b00, mant_b} : {2'b01, mant_b};
            
            // Alinear exponentes (poner el mismo exponente)
            if (exp_a > exp_b) begin
                exp_diff = exp_a - exp_b;
                exp_result = exp_a;
                mant_aligned_a = {2'b0, mant_a_norm};
                mant_aligned_b = {2'b0, mant_b_norm} >> exp_diff;  // Desplazar mantisa menor
            end else begin
                exp_diff = exp_b - exp_a;
                exp_result = exp_b;
                mant_aligned_a = {2'b0, mant_a_norm} >> exp_diff;  // Desplazar mantisa menor
                mant_aligned_b = {2'b0, mant_b_norm};
            end
            
            // Sumar o restar según los signos
            if (sign_a == sign_b_eff) begin
                // Signos iguales: suma efectiva
                mant_sum = mant_aligned_a + mant_aligned_b;
                sign_result = sign_a;
            end else begin
                // Signos diferentes: resta efectiva
                if (mant_aligned_a >= mant_aligned_b) begin
                    mant_sum = mant_aligned_a - mant_aligned_b;
                    sign_result = sign_a;
                end else begin
                    mant_sum = mant_aligned_b - mant_aligned_a;
                    sign_result = sign_b_eff;
                end
            end
            
            // ==========================================
            // Normalizar resultado
            // ==========================================
            
            // Caso 1: Overflow de mantisa (bit en posición 26)
            if (mant_sum[26]) begin
                exp_result = exp_result + 1;
                if (mode_fp)
                    mant_result = mant_sum[26:4];
                else
                    mant_result = {mant_sum[26:17], 13'b0};
                
                // Verificar overflow de exponente
                if (exp_result >= EXP_MAX) begin
                    flags[1] = 1;  // Overflow
                    result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
                end else begin
                    result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
                end
            end
            
            // Caso 2: Ya normalizado (bit en posición 25)
            else if (mant_sum[25]) begin
                if (mode_fp)
                    mant_result = mant_sum[25:3];
                else
                    mant_result = {mant_sum[25:16], 13'b0};
                
                result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
            
            // Caso 3: Resultado es cero
            else if (mant_sum == 0) begin
                result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
            end
            
            // Caso 4: Necesita normalización a la izquierda
            else begin
                // Contar ceros a la izquierda
                leading_zeros = 0;
                for (i = 24; i >= 0; i = i - 1) begin
                    if (mant_sum[i] == 1 && leading_zeros == 0)
                        leading_zeros = 25 - i;
                end
                
                // Verificar underflow
                if (leading_zeros > exp_result) begin
                    flags[0] = 1;  // Underflow
                    result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
                end else begin
                    exp_result = exp_result - leading_zeros;
                    mant_sum = mant_sum << leading_zeros;
                    
                    if (mode_fp)
                        mant_result = mant_sum[25:3];
                    else
                        mant_result = {mant_sum[25:16], 13'b0};
                    
                    result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
                end
            end
        end
    end
    
endmodule

// ==========================================
// Módulo de Multiplicación
// Maneja tanto single (32-bit) como half (16-bit)
// ==========================================
module fp_mul(
    input [31:0] a,
    input [31:0] b,
    input mode_fp,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Extraer campos
    wire sign_a = mode_fp ? a[31] : a[15];
    wire sign_b = mode_fp ? b[31] : b[15];
    wire [7:0] exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    wire [7:0] exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    wire [22:0] mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};
    wire [22:0] mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    wire [7:0] EXP_BIAS = mode_fp ? 8'd127 : 8'd15;
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    reg [47:0] mant_product;
    reg [8:0] exp_sum;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        result = 32'b0;
        sign_result = sign_a ^ sign_b;  // XOR de signos
        
        // Caso NaN
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        
        // Caso 0 * Inf = NaN
        else if ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        
        // Caso Inf * x = Inf
        else if (a_is_inf || b_is_inf) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        
        // Caso 0 * x = 0
        else if (a_is_zero || b_is_zero) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // Multiplicar mantisas
            mant_product = mant_a_norm * mant_b_norm;
            
            // Sumar exponentes y ajustar bias
            exp_sum = exp_a + exp_b;
            if (!a_is_denorm && !b_is_denorm)
                exp_sum = exp_sum - EXP_BIAS;
            
            // Normalizar
            if (mant_product[47]) begin
                exp_result = exp_sum + 1;
                mant_result = mode_fp ? mant_product[46:24] : {mant_product[46:37], 13'b0};
            end else begin
                exp_result = exp_sum;
                mant_result = mode_fp ? mant_product[45:23] : {mant_product[45:36], 13'b0};
            end
            
            // Verificar overflow/underflow
            if (exp_result >= EXP_MAX) begin
                flags[1] = 1;
                result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            end else if (exp_result == 0) begin
                flags[0] = 1;
                result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
            end else begin
                result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
        end
    end
    
endmodule

// ==========================================
// Módulo de División
// Maneja tanto single (32-bit) como half (16-bit)
// ==========================================
module fp_div(
    input [31:0] a,
    input [31:0] b,
    input mode_fp,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    // Extraer campos
    wire sign_a = mode_fp ? a[31] : a[15];
    wire sign_b = mode_fp ? b[31] : b[15];
    wire [7:0] exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    wire [7:0] exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    wire [22:0] mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};
    wire [22:0] mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    wire [7:0] EXP_BIAS = mode_fp ? 8'd127 : 8'd15;
    
    // Detectar casos especiales
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    reg [47:0] mant_quotient;
    reg [8:0] exp_diff;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        result = 32'b0;
        sign_result = sign_a ^ sign_b;
        
        // Caso NaN
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        
        // Caso 0/0 o Inf/Inf = NaN
        else if ((a_is_zero && b_is_zero) || (a_is_inf && b_is_inf)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        
        // Caso x/0 = Inf
        else if (b_is_zero) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            flags[2] = 1;  // Division by zero
        end
        
        // Caso Inf/x = Inf
        else if (a_is_inf) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        
        // Caso x/Inf = 0
        else if (b_is_inf) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        
        // Caso 0/x = 0
        else if (a_is_zero) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        
        // Operación normal
        else begin
            // Agregar bit implícito
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // División de mantisas
            mant_quotient = ({mant_a_norm, 24'b0}) / mant_b_norm;
            
            // Calcular exponente
            exp_diff = exp_a - exp_b + EXP_BIAS;
            if (a_is_denorm) exp_diff = exp_diff - 1;
            if (b_is_denorm) exp_diff = exp_diff + 1;
            
            // Normalizar
            if (mant_quotient[47]) begin
                exp_result = exp_diff + 1;
                mant_result = mode_fp ? mant_quotient[46:24] : {mant_quotient[46:37], 13'b0};
            end else if (mant_quotient[46]) begin
                exp_result = exp_diff;
                mant_result = mode_fp ? mant_quotient[45:23] : {mant_quotient[45:36], 13'b0};
            end else begin
                exp_result = exp_diff - 1;
                mant_result = mode_fp ? mant_quotient[44:22] : {mant_quotient[44:35], 13'b0};
            end
            
            // Verificar overflow/underflow
            if (exp_result >= EXP_MAX) begin
                flags[1] = 1;
                result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            end else if (exp_result == 0) begin
                flags[0] = 1;
                result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
            end else begin
                result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
        end
    end
    
endmodule
