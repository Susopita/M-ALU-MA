`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/18/2025 11:26:08 AM
// Design Name: 
// Module Name: top_basys3
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// top_basys3.v
module top_basys3 (
    // Reloj y Reset
    input           clk,
    // Botones de la Basys 3
    input           btnC,
    input           btnU,
    input           btnD,
    // Interruptores y LEDs
    input  [15:0]   sw,
    output reg [15:0]   led,
    // Display 7-Segmentos
    output [6:0]    seg,
    output [3:0]    an
);

    // ==================================
    // FSM Estados
    // ==================================
    localparam S_IDLE       = 4'd0;
    localparam S_LOAD_A_H   = 4'd1;
    localparam S_LOAD_A_L   = 4'd2;
    localparam S_LOAD_B_H   = 4'd3;
    localparam S_LOAD_B_L   = 4'd4;
    localparam S_CONFIG     = 4'd5;
    localparam S_COMPUTE    = 4'd6;
    localparam S_DISPLAY    = 4'd7;
    localparam S_SHOW_FLAGS = 4'd8;

    reg [3:0] state, next_state;

    // ==================================
    // Registros para guardar datos
    // ==================================
    reg [31:0] reg_op_a;
    reg [31:0] reg_op_b;
    reg [2:0]  reg_op_code;
    reg        reg_mode_fp;
    reg [31:0] reg_result; // <-- NUEVO: Registro para guardar el resultado
    reg [4:0]  reg_flags;  // <-- NUEVO: Registro para guardar las flags

    reg        alu_start;
    reg        show_result; // <-- ✅ NUEVA BANDERA para mantener el resultado visible
    
    // =========================================================
    // ✅ Códigos de 5 bits para nuestros caracteres especiales
    // =========================================================
    localparam CHAR_n = 5'h10;
    localparam CHAR_r = 5'h11;
    localparam CHAR_L = 5'h12;
    localparam CHAR_H = 5'h13;
    localparam BLANK  = 5'h14;
    localparam CHAR_I = 5'h15;
    localparam CHAR_G = 5'h06;
    localparam CHAR_D = 5'h0D;
    localparam CHAR_0 = 5'h00;
    localparam CHAR_F = 5'h0F;
    localparam CHAR_A = 5'h0A;

    // ==================================
    // Conexiones a la ALU
    // ==================================
    wire [31:0] alu_result;
    wire        alu_valid_out;
    wire [4:0]  alu_flags;
    
    mALUma u_ALU (
        .clk(clk),
        .rst(btnU_pulse),
        .start(alu_start),
        .op_a(reg_op_a),
        .op_b(reg_op_b),
        .op_code(reg_op_code),
        .mode_fp(reg_mode_fp),
        .round_mode(1'b0),
        .result(alu_result),
        .valid_out(alu_valid_out),
        .flags(alu_flags)
    );
    
    // =========================================================
    // ✅ Usando el Debouncer
    // =========================================================
    wire btnC_pulse;
    debounce u_debounce_btnC (
        .clk(clk),
        .btn_in(btnC),
        .btn_pulse(btnC_pulse)
    );
    
    //wire btnU_pulse; // <-- Pulso limpio para el botón de reset
    debounce u_debounce_btnU (
        .clk(clk),
        .btn_in(btnU),
        .btn_pulse(btnU_pulse)
    );
    
    wire btnD_pulse;
    debounce u_debounce_btnD (
        .clk(clk),
        .btn_in(btnD),
        .btn_pulse(btnD_pulse)
    );

    // =========================================================
    // ✅ Bloque Síncrono Maestro y Unificado
    // =========================================================
    always @(posedge clk) begin
        if (btnU_pulse) begin
            // --- SECCIÓN DE RESET ---
            state       <= S_IDLE;
            reg_op_a    <= 32'b0;
            reg_op_b    <= 32'b0;
            reg_op_code <= 3'b0;
            reg_mode_fp <= 1'b0;
            reg_result  <= 32'b0;
            reg_flags   <= 5'b0;
            show_result <= 1'b0;
            alu_start   <= 1'b0;
        end else begin
            // --- SECCIÓN DE OPERACIÓN NORMAL ---
    
            // Lógica de la FSM (actualiza el estado y la bandera 'show_result')
            state <= next_state;
            if (next_state == S_DISPLAY)
                show_result <= 1'b1;
            else if (state == S_IDLE && next_state != S_IDLE)
                show_result <= 1'b0;
    
            // Lógica de la ALU
            alu_start <= 1'b0;
            if (state == S_COMPUTE && next_state == S_COMPUTE) begin
                reg_op_code <= sw[2:0];
                reg_mode_fp <= sw[3];
                alu_start <= 1'b1;
            end
    
            // Lógica de Carga de Datos
            if (btnC_pulse) begin
                case (state)
                    S_LOAD_A_H: reg_op_a[31:16] <= sw;
                    S_LOAD_A_L: reg_op_a[15:0]  <= sw;
                    S_LOAD_B_H: reg_op_b[31:16] <= sw;
                    S_LOAD_B_L: reg_op_b[15:0]  <= sw;
                    S_CONFIG: begin
                        reg_op_code <= sw[2:0];
                        reg_mode_fp <= sw[14];
                    end
                endcase
            end
    
            // Captura del resultado de la ALU
            if(alu_valid_out) begin
                reg_result <= alu_result;
                reg_flags  <= alu_flags;
            end
        end
    end
    
    always @(*) begin
        next_state = state;
        if (btnC_pulse) begin // <-- Usamos el pulso limpio del debouncer
            case (state)
                S_IDLE:     next_state = S_LOAD_A_H;
                S_LOAD_A_H: next_state = S_LOAD_A_L;
                S_LOAD_A_L: next_state = S_LOAD_B_H;
                S_LOAD_B_H: next_state = S_LOAD_B_L;
                S_LOAD_B_L: next_state = S_CONFIG;
                S_CONFIG:   next_state = S_COMPUTE;
                S_COMPUTE:  next_state = S_COMPUTE; // Se queda aquí hasta que la ALU termine
                S_DISPLAY:  next_state = S_IDLE;    // Vuelve al inicio en la siguiente pulsación
                default:    next_state = S_IDLE;
            endcase
        end else if (state == S_COMPUTE && alu_valid_out) begin
             // Transición automática cuando la ALU termina
             next_state = S_DISPLAY;
        // <-- NUEVO: Lógica para alternar con btnD
        end else if (btnD_pulse) begin 
            if (state == S_DISPLAY)
                next_state = S_SHOW_FLAGS;
            else if (state == S_SHOW_FLAGS)
                next_state = S_DISPLAY;
        end
    end
    
    // ==================================
    // Lógica de Salida (LEDs)
    // ==================================
    wire [15:0] result_display_bus;
    assign result_display_bus = sw[15] ? reg_result[31:16] : reg_result[15:0];

    // Salida BINARIA a los LEDs
    // <-- MODIFICADO: Lógica de LEDs ahora en un bloque always
    always @(*) begin
        if (state == S_SHOW_FLAGS) begin
            led = 16'b0; // Apaga todos los LEDs por defecto
            led[14:10] = reg_flags; // Muestra las 5 flags en los primeros 5 LEDs
        end else if (show_result) begin
            led = result_display_bus;
        end else begin
            led = 16'b0;
        end
    end

    // Señales de 5 bits para el display
    reg [4:0] display_d3, display_d2, display_d1, display_d0;
    
    always @(*) begin
        if (show_result && state != S_SHOW_FLAGS) begin
            // Si la bandera está activa, SIEMPRE muestra el resultado en hexadecimal
            {display_d3, display_d2, display_d1, display_d0} = {{1'b0, result_display_bus[15:12]}, {1'b0, result_display_bus[11:8]}, {1'b0, result_display_bus[7:4]}, {1'b0, result_display_bus[3:0]}};
        end else begin
            // Si no, muestra los mensajes de la FSM
            case(state)
                S_IDLE:     {display_d3, display_d2, display_d1, display_d0} = {CHAR_0, CHAR_F, CHAR_F, BLANK};
                S_LOAD_A_H: {display_d3, display_d2, display_d1, display_d0} = {CHAR_L, CHAR_D, 5'hA, CHAR_H}; // "Ld A H"
                S_LOAD_A_L: {display_d3, display_d2, display_d1, display_d0} = {CHAR_L, CHAR_D, 5'hA, CHAR_L}; // "Ld A L"
                S_LOAD_B_H: {display_d3, display_d2, display_d1, display_d0} = {CHAR_L, CHAR_D, 5'hB, CHAR_H}; // "Ld b H"
                S_LOAD_B_L: {display_d3, display_d2, display_d1, display_d0} = {CHAR_L, CHAR_D, 5'hB, CHAR_L}; // "Ld b L"
                S_CONFIG:   {display_d3, display_d2, display_d1, display_d0} = {5'hC, 5'h0, CHAR_n, 5'hF};     // "COnF"
                S_SHOW_FLAGS: {display_d3, display_d2, display_d1, display_d0} = {CHAR_F, CHAR_L, CHAR_A, CHAR_G}; // <-- NUEVO: "FLAG"
                default:    {display_d3, display_d2, display_d1, display_d0} = {BLANK, BLANK, BLANK, BLANK}; 
            endcase
        end
    end

    // Instancia del módulo display de 5 bits
    display u_display (
        .clk(clk),
        .digit3(display_d3),
        .digit2(display_d2),
        .digit1(display_d1),
        .digit0(display_d0),
        .seg(seg),
        .an(an)
    );
endmodule


// ====================================================================
// A CONTINUACIÓN, PEGA EL CÓDIGO DEL PDF DIRECTAMENTE AQUÍ
// ====================================================================

module display(
    input clk,
    input [4:0] digit3,
    input [4:0] digit2,
    input [4:0] digit1,
    input [4:0] digit0,
    output [6:0] seg,
    output reg [3:0] an
);
    // Lógica de refresco (sin cambios)
    wire [18:0] slow_clk;
    reg [18:0] counter_reg;
    always@(posedge clk) counter_reg <= counter_reg + 1;
    assign slow_clk = counter_reg;
    
    // Lógica para seleccionar el dígito a mostrar
    reg [4:0] digit_val; // <-- CAMBIO: 5 bits
    always@(*) begin
        case(slow_clk[18:17])
            2'b00: digit_val = digit0;
            2'b01: digit_val = digit1;
            2'b10: digit_val = digit2;
            2'b11: digit_val = digit3;
        endcase
    end

    // Lógica de multiplexing (ánodos)
    always@(*) begin
        case(slow_clk[18:17])
            2'b00: an = 4'b1110;
            2'b01: an = 4'b1101;
            2'b10: an = 4'b1011;
            2'b11: an = 4'b0111;
        endcase
    end
    
    wire [6:0] seg_wire;
    
    // Instancia del conversor de 5 bits
    converter_7seg u_converter(
        .char_code(digit_val),
        .seg(seg_wire)
    );
    
    assign seg = seg_wire;
endmodule

// =========================================================
// ✅ Módulo Conversor Universal de 5 bits (Versión Final)
// =========================================================
module converter_7seg(
    input [4:0] char_code, // <-- CAMBIO: Ahora la entrada es de 5 bits
    output reg [6:0] seg
);
    always@(*) begin
        case(char_code)
            // Códigos 0x00 a 0x0F: Mapeo directo a HEXADECIMAL (0-F)
            5'h00: seg = 7'b1000000; // 0
            5'h01: seg = 7'b1111001; // 1
            5'h02: seg = 7'b0100100; // 2
            5'h03: seg = 7'b0110000; // 3
            5'h04: seg = 7'b0011001; // 4
            5'h05: seg = 7'b0010010; // 5
            5'h06: seg = 7'b0000010; // 6
            5'h07: seg = 7'b1111000; // 7
            5'h08: seg = 7'b0000000; // 8
            5'h09: seg = 7'b0010000; // 9
            5'h0A: seg = 7'b0001000; // A
            5'h0B: seg = 7'b0000011; // b (minúscula)
            5'h0C: seg = 7'b1000110; // C
            5'h0D: seg = 7'b0100001; // d (minúscula)
            5'h0E: seg = 7'b0000110; // E
            5'h0F: seg = 7'b0001110; // F

            // Códigos 0x10 en adelante: Mapeo a LETRAS personalizadas
            5'h10: seg = 7'b0101011; // n (minúscula)
            5'h11: seg = 7'b0101111; // r (minúscula)
            5'h12: seg = 7'b1000111; // L (mayúscula)
            5'h13: seg = 7'b0001001; // H (mayúscula)
            5'h14: seg = 7'b1111111; // Espacio en blanco (BLANK)
            5'h15: seg = 7'b1001111; // I (como 1 pero sin la parte de arriba)
            //5'h16: seg = 7'b1000010; // <-- NUEVO: G (mayúscula)
            // ... puedes seguir añadiendo hasta 5'h1F ...
            
            default: seg = 7'b1111111; // Apagado
        endcase
    end
endmodule

// =========================================================
// ✅ Módulo Debouncer (Anti-rebote)
// =========================================================
module debounce (
    input clk,
    input btn_in,
    output btn_pulse
);
    // Para un reloj de 100MHz, un contador de 20ms es un buen valor
    parameter DEBOUNCE_LIMIT = 2000000;

    reg [21:0] counter_reg = 0;
    reg btn_sync_d1, btn_sync_d2, btn_debounced;
    reg btn_debounced_d1;

    // Sincroniza la entrada del botón para evitar metaestabilidad
    always @(posedge clk) begin
        btn_sync_d1 <= btn_in;
        btn_sync_d2 <= btn_sync_d1;
    end

    // Lógica del temporizador de debouncing
    always @(posedge clk) begin
        if (btn_sync_d2 != btn_debounced) begin
            counter_reg <= 0; // Reinicia el contador si hay un cambio
        end else if (counter_reg < DEBOUNCE_LIMIT) begin
            counter_reg <= counter_reg + 1; // Incrementa si la señal es estable
        end

        if (counter_reg == DEBOUNCE_LIMIT) begin
            btn_debounced <= btn_sync_d2; // Valida la señal estable
        end
    end

    // Genera un pulso limpio de un solo ciclo
    always @(posedge clk) begin
        btn_debounced_d1 <= btn_debounced;
    end
    assign btn_pulse = btn_debounced & ~btn_debounced_d1;
endmodule
