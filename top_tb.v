`timescale 1ns / 1ns

module top_tb;
   // Reloj y Reset
    reg            clk;
    // Botones de la Basys 3
    reg           btnC;
    reg           btnU;
    reg           btnD;
    // Interruptores y LEDs
    reg  [15:0]     sw;
    wire [15:0]    led;
    // Display 7-Segmentos
    wire [6:0]     seg;
    wire [3:0]      an;

    top_basys3 dut (
        .clk(clk), 
        .btnC(btnC), 
        .btnU(btnU), 
        .btnD(btnD),
        .sw(sw), 
        .led(led), 
        .seg(seg), 
        .an(an)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Reloj de 100 MHz
    end

    initial begin
      $dumpfile("waves.vcd");
      $dumpvars(0, dut);
    end

    // Contadores para el resumen final
    integer test_count = 0;
    integer pass_count = 0;

    // Códigos de caracteres para verificar el display
    localparam CHAR_A = 5'h0A, CHAR_B = 5'h0B, CHAR_C = 5'h0C, CHAR_F = 5'h0F,
               CHAR_n = 5'h10, CHAR_L = 5'h12, CHAR_H = 5'h13, BLANK  = 5'h14,
               CHAR_I = 5'h15, CHAR_0 = 5'h00, CHAR_D = 5'h0D;

    // =========================================================
    // TAREAS AUXILIARES PARA SIMULAR ACCIONES
    // =========================================================
    
    // Tarea para simular una pulsación limpia de un botón
    task press_button;
        inout button_reg;
        begin
            @(posedge clk);
            button_reg = 1;
            repeat(3) @(posedge clk); // Mantener presionado por 2 ciclos
            button_reg = 0;
            repeat(6) @(posedge clk); // Esperar un poco antes de la siguiente acción
        end
    endtask
    
    // Tarea para cargar un operando de 32 bits en dos pasos
    task load_operand;
        input [31:0] operand;
        begin
            sw = operand[31:16]; // Parte alta
            press_button(btnC);
            sw = operand[15:0];  // Parte baja
            press_button(btnC);
        end
    endtask

    // =========================================================
    // TAREA DE VERIFICACIÓN PARA EL DISPLAY Y LEDS
    // =========================================================
    task check_outputs;
        input [255:0] test_name;
        input [19:0] expected_display_msg; // 4 dígitos de 5 bits cada uno
        input [15:0] expected_leds;
        
        reg passed;
        begin
            test_count = test_count + 1;
            passed = 1; // Asumimos que pasa hasta que se demuestre lo contrario
            
            // Damos un ciclo para que las señales se estabilicen
            @(posedge clk);

            // Verificamos el mensaje del Display
            // Leemos las señales internas que alimentan al display en el DUT
            if ({dut.display_d3, dut.display_d2, dut.display_d1, dut.display_d0} !== expected_display_msg) begin
                $display("FAIL: [%0s] Mensaje de Display incorrecto.", test_name);
                $display("      Esperado: %s%s%s%s, Obtenido: %s", 
                    decode_char(expected_display_msg[19:15]),
                    decode_char(expected_display_msg[14:10]),
                    decode_char(expected_display_msg[9:5]),
                    decode_char(expected_display_msg[4:0]), 
                    {
                        decode_char(dut.display_d3), 
                        decode_char(dut.display_d2), 
                        decode_char(dut.display_d1), 
                        decode_char(dut.display_d0) 
                    }
                );
                passed = 0;
            end

            // Verificamos los LEDs
            if (led !== expected_leds) begin
                $display("FAIL: [%0s] Valor de LEDs incorrecto.", test_name);
                $display("      Esperado: %b, Obtenido: %b", expected_leds, led);
                passed = 0;
            end

            if (passed) begin
                $display("PASS: [%s]", test_name);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task run_test;
        input [255:0]              name;
        input                     reset;
        input [31:0]               op_a;
        input [31:0]               op_b;
        input [3:0]                conf;
        input [39:0]   expected_display;
        input [31:0]      expected_leds;
  
        reg passed;
        begin
            $display("\n--- INICIANDO PRUEBA: %0s ---\n", name);

            // ==========================================
            // 1. ALU esta inactiva o apagado logico
            // ==========================================
            
            if (reset) begin
                // 1.1. Con boton UP para resetear todo
                press_button(btnU);
                @(posedge clk);
                check_outputs("Reset inicial", {CHAR_0,CHAR_F,CHAR_F,BLANK}, 16'b0);

                // 1.2. Con boton central para seguir a la 
                //      siguiente fase (carga)
                press_button(btnC);
                 
            end

            // ==========================================
            // 2. Fase de Carga del Operador A (32 bits)
            // ==========================================

            // 2.1 Parte Alta (Ld A H) 
            // Display: Mostrara "LdAH" 
            //       (Load part 'A' High)

            // Accion: Recibe los 16 bits superiores de A 
            //         usando los 16 switches
            // sw = 15'b000000000000000;                      // <--  CLUE: bits 31 al 16 

            // Confirmar: Presiona el boton Central para 
            //            confirmar y guardar los bits
            // btnC = 1;

            // 2.2 Parte Baja (Ld A L) 
            // Display: Mostrara "LdAL" 
            //        (Load part 'A' Low)

            // Accion: Recibe los 16 bits inferiores de A 
            //         usando los mismos switches
            // sw = 15'b000000000000000;                      // <--  CLUE: bits 15 al 0

            // Confirmar: Presiona el boton Central para 
            //            confirmar y guardar los bits
            // btnC = 1;
            
            check_outputs("Inicio Carga A (High)", {CHAR_L, CHAR_D, CHAR_A, CHAR_H}, 16'b0);
            load_operand(op_a);

            // ==========================================
            // 3. Fase de Carga del Operador B (32 bits)
            // ==========================================
            
            // 3.1 Parte Alta (Ld B H) 
            // Display: Mostrara "LdBH" 
            //       (Load part 'B' High)

            // Accion: Recibe los 16 bits superiores de A 
            //         usando los 16 switches
            // sw = 15'b000000000000000;                      // <--  CLUE: bits 31 al 16 

            // Confirmar: Presiona el boton Central para 
            //            confirmar y guardar los bits
            // btnC = 1;

            // 3.2 Parte Baja (Ld B L) 
            // Display: Mostrara "LdBL" 
            //        (Load part 'B' Low)

            // Accion: Recibe los 16 bits inferiores de A 
            //         usando los mismos switches
            // sw = 15'b000000000000000;                      // <--  CLUE: bits 15 al 0

            // Confirmar: Presiona el boton Central para 
            //            confirmar y guardar los bits
            // btnC = 1;
            
            check_outputs("Inicio Carga B (High)", {CHAR_L, CHAR_D, CHAR_B, CHAR_H}, 16'b0);
            load_operand(op_b);

            // ==========================================
            // 4. Configuracion y Ejecucion
            // ==========================================
            
            // Display: Mostrara "COnF" (Configuracion)
            check_outputs("Fase de Configuracion", {CHAR_C, CHAR_0, CHAR_n, CHAR_F}, 16'b0);

            // Accion: Usa los interruptores para 
            //         configurar la operacion
            sw [3:0] = {13'b0, conf};

            // Ejecutar: Una vez configurado, 
            //           se presiona btnC. 
            //           La ALU comenzará el cálculo. 
            //           El display se apagará 
            //           momentáneamente.
            press_button(btnC);
            $display("... Esperando resultado del cálculo ...");
            wait(dut.show_result == 1); // Espera a que el resultado esté listo para mostrarse


            // ==========================================
            // 5. Visualizacion de Resultado
            // ==========================================
            
            // Luego del calculo, el resultado 
            // aparecerá en dos formatos al mismo tiempo
            
            // Display 7-Segmentos: Muestra el resultado 
            //                      en hexadecimal.

            // LEDs: Muestran el resultado en binario.
            
            // Acción para ver el resultado completo:
            //      1'b0 <-- abajo  (por defecto)
            //      1'b1 <-- arriba
            sw[15] = 1'b0;                                 // <-- CLUE: 16 bits inferiores (bits 15 al 0).
                                                          //           Tanto el Display como LEDs 
                                                          //           mostraran estos bits 
                                                          //           en sus formatos.
            check_outputs(
                "Resultado (Parte Baja)", 
                expected_display[19:0], 
                expected_leds[15:0]
            );

            sw[15] = 1'b1;                                 // <-- CLUE: 16 bits superiores (bits 31 al 16).
                                                          //           Tanto el Display como LEDs 
                                                          //           mostraran estos bits 
                                                          //           en sus formatos.
            check_outputs(
                "Resultado (Parte Alta)", 
                expected_display[39:20], 
                expected_leds[31:16]
            );


            // El resultado permanecerá visible en 
            // pantalla hasta el proximo calculo.
            press_button(btnC);
            check_outputs("Vuelta al estado IDLE", {BLANK,BLANK,BLANK,BLANK}, 16'b0);


            // ==========================================
            // 6. Nuevo calculo
            // ==========================================
            press_button(btnC);
        end
    endtask
    
    initial begin
        $display("\n=================================================");
        $display("  TESTBENCH - top_basys3 ");
        $display("=================================================\n");

        btnC = 0; btnU = 0; btnD = 0; sw = 16'b0;
        #20;

        // 1) 2.0 + 3.0 = 5.0
        run_test("2.0 + 3.0 = 5.0 (32 bits)", 1, 32'h40000000, 32'h40400000, {1'b1, 3'b000}, {5'h04,5'h00,5'h0A,5'h00,5'h00,5'h00,5'h00,5'h00}, 32'h40A00000);

        // Resumen final
        $display("\n=================================================");
        $display("  RESUMEN FINAL");
        $display("  Pruebas Totales: %0d", test_count);
        $display("  Pruebas Pasadas: %0d", pass_count);
        $display("=================================================\n");

        $finish;
    end

    // =========================================================
    // ✅ FUNCIÓN PARA DECODIFICAR UN CÓDIGO DE 5 BITS A UN CARACTER
    // =========================================================
    function [7:0] decode_char(input [4:0] code);
        begin
            case(code)
                // Códigos 0x00 a 0x0F: Mapeo a caracteres ASCII de 0-9 y A-F
                5'h00: decode_char = "0"; // Equivale a 8'h30
                5'h01: decode_char = "1"; // Equivale a 8'h31
                5'h02: decode_char = "2";
                5'h03: decode_char = "3";
                5'h04: decode_char = "4";
                5'h05: decode_char = "5";
                5'h06: decode_char = "6";
                5'h07: decode_char = "7";
                5'h08: decode_char = "8";
                5'h09: decode_char = "9";
                5'h0A: decode_char = "A"; // Equivale a 8'h41
                5'h0B: decode_char = "B";
                5'h0C: decode_char = "C";
                5'h0D: decode_char = "d";
                5'h0E: decode_char = "E";
                5'h0F: decode_char = "F";

                // Códigos 0x10 en adelante: Mapeo a LETRAS personalizadas
                5'h10: decode_char = "n";
                5'h11: decode_char = "r";
                5'h12: decode_char = "L";
                5'h13: decode_char = "H";
                5'h14: decode_char = "_"; // Espacio en blanco
                5'h15: decode_char = "I";
                
                default: decode_char = "?"; // Carácter de interrogación
            endcase
        end
    endfunction
endmodule
