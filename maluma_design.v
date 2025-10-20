// ==============================
// ALU Punto Flotante IEEE-754 
// ==============================

`timescale 1ns / 1ns

// Módulo Principal de la ALU
module mALUma(
    input clk,
    input rst,
    input start,
    input [31:0] op_a,          
    input [31:0] op_b,          
    input [2:0] op_code,        // Código operación: 000=ADD, 001=SUB, 010=MUL, 011=DIV
    input mode_fp,              // 0=half(16-bit), 1=single(32-bit)
    input round_mode,           // Modo redondeo: 0=nearest even
    output reg [31:0] result,   
    output reg valid_out,       
    output reg [4:0] flags      // [4:inexact, 3:invalid, 2:div_by_zero, 1:overflow, 0:underflow]
);

    parameter IDLE    = 1'b0;
    parameter COMPUTE = 1'b1;
    
    reg state, next_state;
    
    wire [31:0] result_add_32, result_sub_32, result_mul, result_div;
    wire [15:0] result_add_16, result_sub_16;
    wire [4:0] flags_add_32, flags_sub_32, flags_add_16, flags_sub_16, flags_mul, flags_div;
    reg [31:0] result_selected;
    reg [4:0] flags_selected;
    
    SumSub #(
        .E_BITS(8),
        .M_BITS(23)
    ) suma_32 (
        .A(op_a), .B(op_b),
        .op(1'b0),
        .Result(result_add_32),
        .ALUFlags(flags_add_32)
    );

    SumSub #(
        .E_BITS(5),
        .M_BITS(10)
    ) suma_16 (
        .A(op_a), .B(op_b),
        .op(1'b0),
        .Result(result_add_16),
        .ALUFlags(flags_add_16)
    );
    
    SumSub #(
        .E_BITS(8),
        .M_BITS(23)
    ) resta_32 (
        .A(op_a), .B(op_b),
        .op(1'b1),
        .Result(result_sub_32),
        .ALUFlags(flags_sub_32)
    );

    SumSub #(
        .E_BITS(5),
        .M_BITS(10)
    ) resta_16 (
        .A(op_a), .B(op_b),
        .op(1'b1),
        .Result(result_sub_16),
        .ALUFlags(flags_sub_16)
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
    
    always @(*) begin
        case (op_code[1:0])
            2'b00: begin
                if (mode_fp) begin
                    result_selected = result_add_32;
                    flags_selected = flags_add_32;
                end else begin
                    result_selected = result_add_16;
                    flags_selected = flags_add_16;
                end
            end
            2'b01: begin
                if (mode_fp) begin
                    result_selected = result_sub_32;
                    flags_selected = flags_sub_32;
                end else begin
                    result_selected = result_sub_16;
                    flags_selected = flags_sub_16;
                end
            end
            2'b10: begin
                result_selected = result_mul;
                flags_selected = flags_mul;
            end
            2'b11: begin
                result_selected = result_div;
                flags_selected = flags_div;
            end
        endcase
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    always @(*) begin
        case (state)
            IDLE: begin
                if (start)
                    next_state = COMPUTE;
                else
                    next_state = IDLE;
            end
            COMPUTE: begin
                next_state = IDLE;
            end
            default: 
                next_state = IDLE;
        endcase
    end
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result <= 32'b0;
            flags <= 5'b0;
            valid_out <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    valid_out <= 1'b0;
                end
                COMPUTE: begin
                    result <= result_selected;
                    flags <= flags_selected;
                    valid_out <= 1'b1;
                end
            endcase
        end
    end

endmodule

module SumSub #(
    // ✅ PARÁMETROS PRINCIPALES: Ancho de Exponente y Mantisa
    parameter E_BITS = 8,
    parameter M_BITS = 23
) (
    // ✅ PUERTOS GENÉRICOS: El ancho total se calcula automáticamente
    input [1+E_BITS+M_BITS-1:0] A, B,
    input                       op,
    output reg [1+E_BITS+M_BITS-1:0] Result,
    output reg [4:0]                 ALUFlags
);
    // =================================================================
    // ✅ PARÁMETROS LOCALES (calculados a partir de los principales)
    // =================================================================
    localparam BITS = 1 + E_BITS + M_BITS;
    localparam EXP_MAX = {E_BITS{1'b1}};
    // Ancho para la mantisa extendida: {Overflow, Implícito, Mantisa, G, R, S}
    localparam MANT_EXT_WIDTH = M_BITS + 5;

    // =================================================================
    // ✅ DECONSTRUCCIÓN PARAMETRIZADA
    // =================================================================
    wire s_A = A[BITS-1];
    wire [E_BITS-1:0] e_A = A[BITS-2 : M_BITS];
    wire [M_BITS-1:0] m_A = A[M_BITS-1 : 0];

    wire s_B = B[BITS-1];
    wire [E_BITS-1:0] e_B = B[BITS-2 : M_BITS];
    wire [M_BITS-1:0] m_B = B[M_BITS-1 : 0];

    wire effective_s_B = op ? ~s_B : s_B;
    
    // =================================================================
    // ✅ REGISTROS INTERNOS PARAMETRIZADOS
    // =================================================================
    reg s_C;
    reg [E_BITS-1:0] e_C;
    reg [MANT_EXT_WIDTH-1:0] m_C; // Usa el ancho extendido calculado

    reg [MANT_EXT_WIDTH-1:0] m_A_full, m_B_full;

    integer i;
    reg [$clog2(M_BITS+1)-1:0] zeros = 0; // Ancho calculado para 'zeros'

    reg [E_BITS-1:0] shift_amount; // Ancho calculado para 'shift_amount'
    reg R_bit, S_bit;
    reg round_up;
    reg [MANT_EXT_WIDTH-1:0] sticky_mask;

    // ✅ Registros para cada flag
    reg flag_invalid, flag_div_zero, flag_overflow, flag_underflow, flag_inexact;

    // =================================================================
    // ✅ DETECCIÓN DE CASOS ESPECIALES PARAMETRIZADA
    // =================================================================
    wire is_zero_A = (e_A == 0 && m_A == 0);
    wire is_inf_A  = (e_A == EXP_MAX && m_A == 0);
    wire is_nan_A  = (e_A == EXP_MAX && m_A != 0);

    wire is_zero_B = (e_B == 0 && m_B == 0);
    wire is_inf_B  = (e_B == EXP_MAX && m_B == 0);
    wire is_nan_B  = (e_B == EXP_MAX && m_B != 0);
    // Sumar
    always @(*) begin

        // ✅ Inicializar flags a 0 en cada ciclo
        flag_invalid = 1'b0;
        flag_div_zero = 1'b0; // Siempre 0 para suma/resta
        flag_overflow = 1'b0;
        flag_underflow = 1'b0;
        flag_inexact = 1'b0;
 
        // =================================================================
        // ✅ APLICAR LAS REGLAS DE LA ARITMÉTICA ESPECIAL
        // =================================================================
        // La lógica de prioridad es: NaN > Infinito > Cero > Normal

        // --- MANEJO DE CASOS ESPECIALES ---
        if (is_nan_A || is_nan_B) begin
            Result = {1'b0, EXP_MAX, {1'b1, {M_BITS-1{1'b0}}}}; // NaN genérico
            flag_invalid = 1'b1;
        end else if (is_inf_A) begin
            if (is_inf_B && (s_A != effective_s_B)) begin
                Result = {1'b0, EXP_MAX, {1'b1, {M_BITS-1{1'b0}}}}; // NaN
                flag_invalid = 1'b1;
            end else Result = A;
        end else if (is_inf_B) begin
            Result = {effective_s_B, EXP_MAX, {M_BITS{1'b0}}};
        end else if (is_zero_A) begin
            Result = {effective_s_B, e_B, m_B};
        end else if (is_zero_B) begin
            Result = A;
        end else begin

            // ==============================
            // Inicializacion
            // ==============================

            m_A_full = {2'b01, m_A, 3'b000};
            m_B_full = {2'b01, m_B, 3'b000};

            // Nivelar exponentes
            if (e_A > e_B) begin
                shift_amount = e_A - e_B;
                e_C = e_A;
                // Para calcular R y S, creamos un 'sticky_mask'
                // El 'OR' de los bits que se caerán (excepto el primero) será el Sticky Bit.
                if (shift_amount > 0) begin
                    R_bit = m_B_full[shift_amount - 1 + 3];
                    sticky_mask = (1 << shift_amount) - 1;
                    S_bit = |(m_B_full & sticky_mask);
                end
                m_B_full = m_B_full >> shift_amount;
            end 
            else if (e_B > e_A) begin
                shift_amount = e_B - e_A;
                e_C = e_B;
                if (shift_amount > 0) begin
                    R_bit = m_A_full[shift_amount - 1 + 3];
                    sticky_mask = (1 << shift_amount) - 1;
                    S_bit = |(m_A_full & sticky_mask);
                end
                m_A_full = m_A_full >> shift_amount;
            end else begin
                e_C = e_A; // Exponentes ya son iguales
            end

            // Sumar mantisas
            if (s_A == effective_s_B) begin
                m_C = m_A_full + m_B_full;
                s_C = s_A;
            end
            else if (m_A_full >= m_B_full) begin
                m_C = m_A_full - m_B_full;
                s_C = s_A;
            end else begin
                m_C = m_B_full - m_A_full;
                s_C = s_B;
            end


            // ✅ FLAG: Si se perdieron bits en la alineación, el resultado será inexacto
            if (R_bit || S_bit) begin
                flag_inexact = 1'b1;
            end
            

            // --- NORMALIZACIÓN, REDONDEO Y ENSAMBLADO FINAL ---
            if (m_C == 0) begin
                s_C = 1'b0; // x-x siempre es +0
                e_C = 0;
                Result = {s_C, {E_BITS{1'b0}}, {M_BITS{1'b0}}};
            end else begin
                // NORMALIZACIÓN
                if (m_C[M_BITS+4]) begin // Overflow de mantisa
                    R_bit = m_C[0]; S_bit = R_bit | S_bit;
                    m_C = m_C >> 1;
                    e_C = e_C + 1;
                end else if (~m_C[M_BITS+3]) begin // Leading zeros
                    zeros = 0;
                    for (i = M_BITS+2; i >= 3; i = i - 1) begin
                        if (m_C[i]) zeros = (M_BITS+3) - i;
                    end
                    if (e_C > zeros) begin
                        m_C = m_C << zeros;
                        e_C = e_C - zeros;
                    end else begin
                        flag_underflow = 1'b1; flag_inexact = 1'b1;
                        m_C = 0; e_C = 0;
                    end
                end

                // REDONDEO
                round_up = R_bit && (S_bit || m_C[3]);
                if (round_up) begin
                    flag_inexact = 1'b1;
                    m_C = m_C + (1 << 3);
                    if (m_C[M_BITS+4]) begin
                        m_C = m_C >> 1;
                        e_C = e_C + 1;
                    end
                end

                // CHEQUEO FINAL y ENSAMBLADO
                if (e_C >= EXP_MAX) begin
                    flag_overflow = 1'b1; flag_inexact = 1'b1;
                    Result = {s_C, EXP_MAX, {M_BITS{1'b0}}};
                end else begin
                    Result = {s_C, e_C, m_C[M_BITS+2 : 3]};
                end            
            end
        end
        // ✅ Ensamblado final de las flags
        ALUFlags = {flag_inexact, flag_invalid, flag_div_zero, flag_overflow, flag_underflow};
    end
endmodule

// Módulo de Multiplicación
module fp_mul(
    input [31:0] a,
    input [31:0] b,
    input mode_fp,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    wire sign_a = mode_fp ? a[31] : a[15];
    wire sign_b = mode_fp ? b[31] : b[15];
    wire [7:0] exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    wire [7:0] exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    wire [22:0] mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};
    wire [22:0] mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    wire [7:0] EXP_BIAS = mode_fp ? 8'd127 : 8'd15;
    
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    reg [47:0] mant_product;
    reg [9:0] exp_sum;
    reg sign_result;
    reg [8:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    always @(*) begin
        flags = 5'b0;
        result = 32'b0;
        sign_result = sign_a ^ sign_b;
        
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if ((a_is_zero && b_is_inf) || (a_is_inf && b_is_zero)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if (a_is_inf || b_is_inf) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        else if (a_is_zero || b_is_zero) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        else begin
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            mant_product = mant_a_norm * mant_b_norm;
            
            exp_sum = {2'b0, exp_a} + {2'b0, exp_b};
            if (!a_is_denorm && !b_is_denorm)
                exp_sum = exp_sum - {2'b0, EXP_BIAS};
            
            if (mant_product[47]) begin
                exp_result = exp_sum[8:0] + 1;
                mant_result = mode_fp ? mant_product[46:24] : {mant_product[46:37], 13'b0};
            end else begin
                exp_result = exp_sum[8:0];
                mant_result = mode_fp ? mant_product[45:23] : {mant_product[45:36], 13'b0};
            end
            
            if (exp_result >= EXP_MAX) begin
                flags[1] = 1;
                result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            end else if (exp_result == 0) begin
                flags[0] = 1;
                result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
            end else begin
                result = mode_fp ? {sign_result, exp_result[7:0], mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
        end
    end
    
endmodule

// Módulo de División 
module fp_div(
    input [31:0] a,
    input [31:0] b,
    input mode_fp,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    wire sign_a = mode_fp ? a[31] : a[15];
    wire sign_b = mode_fp ? b[31] : b[15];
    wire [7:0] exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    wire [7:0] exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    wire [22:0] mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};
    wire [22:0] mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    wire [7:0] EXP_BIAS = mode_fp ? 8'd127 : 8'd15;
    
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    reg [47:0] mant_quotient;
    reg signed [9:0] exp_result_temp;
    reg sign_result;
    reg [8:0] exp_result;
    reg [22:0] mant_result;
    reg [23:0] mant_a_norm, mant_b_norm;
    
    integer shift_amount;
    
    always @(*) begin
        flags = 5'b0;
        result = 32'b0;
        sign_result = sign_a ^ sign_b;
        
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if ((a_is_zero && b_is_zero) || (a_is_inf && b_is_inf)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if (b_is_zero) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            flags[2] = 1;
        end
        else if (a_is_inf) begin
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        else if (b_is_inf) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        else if (a_is_zero) begin
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        else begin
            // Normalizar mantisas (24 bits con bit implícito)
            mant_a_norm = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};
            
            // División con shift de 23 bits para precisión correcta. Coloca el cociente con el bit implícito en posición 23
            mant_quotient = ({mant_a_norm, 23'b0}) / mant_b_norm;
            
            // Calcular exponente base: exp_a - exp_b + BIAS
            if (!a_is_denorm && !b_is_denorm) begin
                exp_result_temp = $signed({2'b0, exp_a}) - $signed({2'b0, exp_b}) + $signed({2'b0, EXP_BIAS});
            end else if (a_is_denorm && !b_is_denorm) begin
                exp_result_temp = $signed(10'd1) - $signed({2'b0, exp_b}) + $signed({2'b0, EXP_BIAS});
            end else if (!a_is_denorm && b_is_denorm) begin
                exp_result_temp = $signed({2'b0, exp_a}) - $signed(10'd1) + $signed({2'b0, EXP_BIAS});
            end else begin
                exp_result_temp = $signed({2'b0, EXP_BIAS});
            end
            
          // Normalizar el cociente
          // Con shift de 23, el bit implícito debería estar en posición 23 (si mant_a >= mant_b) o en posición 22 (si mant_a < mant_b)
            if (mant_quotient[23]) begin
                // Resultado normalizado: bit implícito en posición 23
                exp_result = exp_result_temp[8:0];
                mant_result = mode_fp ? mant_quotient[22:0] : {mant_quotient[22:13], 13'b0};
            end else if (mant_quotient[22]) begin
                // Necesita shift left 1: bit implícito en posición 22
                mant_quotient = mant_quotient << 1;
                exp_result = exp_result_temp[8:0] - 1;
                mant_result = mode_fp ? mant_quotient[22:0] : {mant_quotient[22:13], 13'b0};
            end else begin
                // Caso especial: resultado muy pequeño, normalizar buscando el primer 1
                shift_amount = 0;
                
                // Buscar el primer bit 1 desde bit 21 hacia abajo
                if (mant_quotient[21]) shift_amount = 2;
                else if (mant_quotient[20]) shift_amount = 3;
                else if (mant_quotient[19]) shift_amount = 4;
                else if (mant_quotient[18]) shift_amount = 5;
                else if (mant_quotient[17]) shift_amount = 6;
                else if (mant_quotient[16]) shift_amount = 7;
                else if (mant_quotient[15]) shift_amount = 8;
                else shift_amount = 9; // O resultado es cero (underflow)
                
                mant_quotient = mant_quotient << shift_amount;
                exp_result = exp_result_temp[8:0] - shift_amount;
                mant_result = mode_fp ? mant_quotient[22:0] : {mant_quotient[22:13], 13'b0};
            end
            
            // Verificar overflow/underflow
            if (exp_result >= EXP_MAX || exp_result_temp >= EXP_MAX) begin
                flags[1] = 1;
                result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
            end else if (exp_result_temp <= 0) begin
                flags[0] = 1;
                result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
            end else begin
                result = mode_fp ? {sign_result, exp_result[7:0], mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
        end
    end
    
endmodule
