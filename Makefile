# =========================================================
# Herramientas y Nombres de Archivos por Defecto
# =========================================================
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

VCD_FILE = waves.vcd

# =========================================================
# Definición de los Archivos Fuente para cada Prueba
# =========================================================

# Archivos de diseño para la prueba de la ALU
ALU_DESIGN_FILES = maluma_design.v

# Testbench para la ALU
ALU_TB_FILE = maluma_tb.v

# Archivos de diseño para la prueba del TOP (incluye todo el diseño)
TOP_DESIGN_FILES = top.v $(ALU_DESIGN_FILES)

# Testbench para el TOP
TOP_TB_FILE = top_tb.v

# =========================================================
# Objetivos Principales (Lo que escribes en la terminal)
# =========================================================
.PHONY: all test_alu test_top view clean

# El objetivo por defecto será probar el módulo TOP
all: test_top

# --- Objetivo para probar solo la ALU ---
test_alu:
	$(IVERILOG) -o alu_test $(ALU_DESIGN_FILES) $(ALU_TB_FILE)
	$(VVP) alu_test

# --- Objetivo para probar el sistema completo (TOP) ---
test_top:
	$(IVERILOG) -o top_test $(TOP_DESIGN_FILES) $(TOP_TB_FILE)
	$(VVP) top_test

# =========================================================
# Objetivos Auxiliares
# =========================================================

# Regla para abrir GTKWave con el archivo de ondas
# Se asume que tu testbench tiene la línea `$dumpfile("waves.vcd");`
view:
	$(GTKWAVE) $(VCD_FILE) &

# Regla para limpiar todos los archivos generados por ambas pruebas
clean:
	rm -f alu_test top_test $(VCD_FILE)
