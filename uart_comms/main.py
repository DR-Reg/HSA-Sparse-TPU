from utility import *
import time

port = SerialPort("COM59")
# port.close()
# REMEMBER: only send in groups of 4 bytes!
# port.write_data([0xBA, 0xDB, 0xAD, 0xFF])
try:
    # remember matrix should come in transposed
    sys_start = time.time()
    start_time = port.write_data([2,1], [[2,4],[3,5]], 2)
    result, end_time = port.read_data(2, verb = 1)
    sys_end = time.time()
    
    fpga_delta = end_time - start_time
    sys_delta = sys_end - sys_start
    print("Received:", result, "sys: %.2f s, fpga: %.6f s" % (sys_delta, fpga_delta))
except KeyboardInterrupt:
    port.close()
    exit()
