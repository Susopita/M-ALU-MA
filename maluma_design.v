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
    
    wire [31:0] result_add, result_sub, result_mul, result_div;
    wire [4:0] flags_add, flags_sub, flags_mul, flags_div;
    
    reg [31:0] result_selected;
    reg [4:0] flags_selected;
    
    fp_add_sub add_module(
        .a(op_a),
        .b(op_b),
        .add_sub(1'b0),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result_add),
        .flags(flags_add)
    );
    
    fp_add_sub sub_module(
        .a(op_a),
        .b(op_b),
        .add_sub(1'b1),
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
    
    always @(*) begin
        case (op_code[1:0])
            2'b00: begin
                result_selected = result_add;
                flags_selected = flags_add;
            end
            2'b01: begin
                result_selected = result_sub;
                flags_selected = flags_sub;
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

// Módulo de Suma/Resta
module fp_add_sub(
    input [31:0] a,
    input [31:0] b,
    input add_sub,
    input mode_fp,
    input round_mode,
    output reg [31:0] result,
    output reg [4:0] flags
);
    
    wire sign_a, sign_b_eff;
    wire [7:0] exp_a, exp_b;
    wire [22:0] mant_a, mant_b;
    
    assign sign_a = mode_fp ? a[31] : a[15];
    assign sign_b_eff = mode_fp ? (b[31] ^ add_sub) : (b[15] ^ add_sub);
    assign exp_a = mode_fp ? a[30:23] : {3'b0, a[14:10]};
    assign exp_b = mode_fp ? b[30:23] : {3'b0, b[14:10]};
    assign mant_a = mode_fp ? a[22:0] : {a[9:0], 13'b0};
    assign mant_b = mode_fp ? b[22:0] : {b[9:0], 13'b0};
    
    wire [7:0] EXP_MAX = mode_fp ? 8'd255 : 8'd31;
    
    wire a_is_nan = (exp_a == EXP_MAX) && (mant_a != 0);
    wire b_is_nan = (exp_b == EXP_MAX) && (mant_b != 0);
    wire a_is_inf = (exp_a == EXP_MAX) && (mant_a == 0);
    wire b_is_inf = (exp_b == EXP_MAX) && (mant_b == 0);
    wire a_is_zero = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero = (exp_b == 0) && (mant_b == 0);
    wire a_is_denorm = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm = (exp_b == 0) && (mant_b != 0);
    
    reg [23:0] mant_a_norm, mant_b_norm;
    reg [7:0] exp_larger;
    reg [7:0] exp_diff;
    reg [47:0] mant_a_aligned, mant_b_aligned;
    reg [48:0] mant_sum;
    reg sign_result;
    reg [7:0] exp_result;
    reg [22:0] mant_result;
    integer j, shift_cnt;
    
    always @(*) begin
        flags = 5'b0;
        result = 32'b0;
        
        if (a_is_nan || b_is_nan) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if (a_is_inf && b_is_inf && (sign_a != sign_b_eff)) begin
            result = mode_fp ? 32'h7FC00000 : {16'b0, 16'h7E00};
            flags[3] = 1;
        end
        else if (a_is_inf || b_is_inf) begin
            sign_result = a_is_inf ? sign_a : sign_b_eff;
            result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
        end
        else if (a_is_zero && b_is_zero) begin
            sign_result = sign_a & sign_b_eff;
            result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
        end
        else if (a_is_zero) begin
            result = mode_fp ? {sign_b_eff, b[30:0]} : {16'b0, sign_b_eff, b[14:0]};
        end
        else if (b_is_zero) begin
            result = a;
        end
        else begin
            mant_a_norm = a_is_denorm ? 24'b0 : {1'b1, mant_a};
            mant_b_norm = b_is_denorm ? 24'b0 : {1'b1, mant_b};
            
            if (exp_a > exp_b) begin
                exp_larger = exp_a;
                exp_diff = exp_a - exp_b;
                mant_a_aligned = {mant_a_norm, 24'b0};
                mant_b_aligned = ({mant_b_norm, 24'b0} >> exp_diff);
            end else begin
                exp_larger = exp_b;
                exp_diff = exp_b - exp_a;
                mant_a_aligned = ({mant_a_norm, 24'b0} >> exp_diff);
                mant_b_aligned = {mant_b_norm, 24'b0};
            end
            
            if (sign_a == sign_b_eff) begin
                mant_sum = {1'b0, mant_a_aligned} + {1'b0, mant_b_aligned};
                sign_result = sign_a;
            end else begin
                if (mant_a_aligned >= mant_b_aligned) begin
                    mant_sum = {1'b0, (mant_a_aligned - mant_b_aligned)};
                    sign_result = sign_a;
                end else begin
                    mant_sum = {1'b0, (mant_b_aligned - mant_a_aligned)};
                    sign_result = sign_b_eff;
                end
            end
            
            exp_result = exp_larger;
            
            if (mant_sum[48]) begin
                mant_result = mode_fp ? mant_sum[47:25] : {mant_sum[47:38], 13'b0};
                exp_result = exp_result + 1;
                if (exp_result >= EXP_MAX) begin
                    flags[1] = 1;
                    result = mode_fp ? {sign_result, 8'hFF, 23'b0} : {16'b0, sign_result, 5'h1F, 10'b0};
                end else begin
                    result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
                end
            end
            else if (mant_sum[47]) begin
                mant_result = mode_fp ? mant_sum[46:24] : {mant_sum[46:37], 13'b0};
                result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
            end
            else if (mant_sum == 0) begin
                result = mode_fp ? {sign_result, 31'b0} : {16'b0, sign_result, 15'b0};
            end
            else begin
                begin : NORMALIZE_BLOCK
                    shift_cnt = 47; // Valor por defecto si no se encuentra ningún '1'
                    for (j = 46; j >= 0; j = j - 1) begin
                        if (mant_sum[j]) begin
                            // La cantidad de shift es la distancia desde la posición objetivo (46)
                            shift_cnt = 46 - j; 
                        end
                    end
                end
                
                if (shift_cnt >= exp_result) begin
                    flags[0] = 1;
                    result = mode_fp ? {sign_result, 8'h00, 23'b0} : {16'b0, sign_result, 5'h00, 10'b0};
                end else begin
                    exp_result = exp_result - shift_cnt;
                    mant_sum = mant_sum << shift_cnt;
                    mant_result = mode_fp ? mant_sum[46:24] : {mant_sum[46:37], 13'b0};
                    result = mode_fp ? {sign_result, exp_result, mant_result} : {16'b0, sign_result, exp_result[4:0], mant_result[22:13]};
                end
            end
        end
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
