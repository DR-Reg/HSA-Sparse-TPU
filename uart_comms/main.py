from utility import *

port = SerialPort("COM59")
# port.close()
# REMEMBER: only send in groups of 4 bytes!
port.write_data([0xBA, 0xDB, 0xAD, 0xFF])
try:
    port.read_data(10, verb = 1)
except KeyboardInterrupt:
    port.close()
    exit()

# result = read_data("COM59", 2, verb=1)
# print("Received:", result)
