from utility import *
import time
import random
import numpy as np

port = SAUnit("COM35", baudrate=921600, N=2)
NUM_RUNS = 20
try:
    # tot_sys_del = tot_fp_del = 0
    # total_corr = 0
    # for i in range(NUM_RUNS):
    #     port.reset(fpga=True)
    #     print(f"================== Performing run {i+1}... ==================")
    #     corr, fdel, sysdel = port.rand_test(vector_mode=0, verb=1)
    #     print("Result:","OK" if corr else "FAIL", end=" ")
    #     print(f"sys: {sysdel:.2f}s, fpga: {fdel:.5f}s")
    #     tot_sys_del += sysdel
    #     tot_fp_del += fdel
    #     if corr:
    #         total_corr += 1
    #     time.sleep(0.1)
    # print(f"{total_corr}/{NUM_RUNS} correct, total sys: {tot_sys_del:.2f}, total fp: {tot_fp_del:.5f}")

    # port.switch_mode(1) # this performs reset of fpga
    corr, fdel, sysdel = port.rand_test(vector_mode=1, verb=1)
    print(corr, fdel, sysdel)

except KeyboardInterrupt:
    print("KBD interrupt, stopping")
finally:
    port.close()
