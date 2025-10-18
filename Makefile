# Define el compilador y el simulador
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Nombre del archivo de salida compilado y del archivo VCD
TARGET = maluma_tests
VCD_FILE = waves.vcd

# Lista todos los archivos de código Verilog (incluyendo el testbench)
VERILOG_FILES = design/Maluma.vl design/SumSub.vl test/Maluma_tb.vl

# Regla principal para compilar y simular (ejecutar por defecto)
all: compile simulate view

# Regla para compilar todos los archivos Verilog
compile: $(VERILOG_FILES)
	$(IVERILOG) -o $(TARGET) $(VERILOG_FILES)

# Regla para ejecutar la simulación
simulate: $(TARGET)
	$(VVP) $(TARGET)

# Regla para abrir GTKWave (asume que el testbench genera el VCD_FILE)
view: $(VCD_FILE)
	$(GTKWAVE) $(VCD_FILE) &

# Regla para limpiar los archivos generados
clean:
	rm -f $(TARGET) $(VCD_FILE)
	
# No se necesitan archivos con estos nombres (importante para make)
.PHONY: all compile simulate view clean
