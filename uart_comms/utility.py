import serial
import time
import numpy as np
import random

class SAUnit:
    def __init__(self, port, N=8, baudrate=921600, timeout=1):
        self.ser = serial.Serial(
            port=port,
            baudrate=baudrate,
            stopbits=serial.STOPBITS_ONE,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_EVEN,
            timeout=timeout
        )

        self.baudrate = baudrate
        self.timeout = timeout
        self.port = port
        self.N = N

        time.sleep(2)   # Stabilise

        if self.ser.is_open:
            self.reset()
        else:   
            raise Exception(f"Unable to open port {port}")

    def switch_mode(self, vector_mode):
        if vector_mode:     # switch to vector mode
            self.ser.write(bytes([0xFE]*4))
        else:
            self.ser.write(bytes([0xFD]*4))
        self.ser.flush()

    def rand_test(self, vector_mode=1, verb=0):
        N = self.N
        if vector_mode:
            acts = [random.randint(0, 100) for i in range(N)]
        else:
            acts = [[random.randint(0, 100) for i in range(N)] for j in range(N)]
        
        weights = [[random.randint(0, 100) for i in range(N)] for j in range(N)]

        npwght = np.array(weights).T
        npacts = np.array(acts)
        nresult = np.matmul(npwght, npacts) # expected result

        sys_start = time.time()
        succ, start_time = self.write_data(acts, weights, vector_mode=vector_mode, verb=verb, max_resends=5)

        result, end_time = self.read_data(vector_mode=vector_mode, verb=verb)
        sys_end = time.time()
        
        fpga_delta = end_time - start_time
        sys_delta = sys_end - sys_start
    
        recv_res = np.array(result)
        correct = np.array_equal(recv_res, nresult)
        return (correct, fpga_delta, sys_delta)
    
    def reset(self, fpga=False):
        self.ser.reset_input_buffer()
        self.ser.reset_output_buffer()
        if fpga:
            for _ in range(5):
                self.ser.write(bytes([0xFF]*4))
            self.ser.flush()

    def read_data(self, vector_mode=1, verb=0):
        if vector_mode:
            result = [None for i in range(self.N)]
        else:
            result = [[None for i in range(self.N)] for j in range(self.N)]

        # Note: removed saturating counter, trust UART...
        mis_align = 0
        ret_time = 0
        set_time = False
        
        while True:
            if self.ser.in_waiting >= 4:
                if not set_time:
                    ret_time = time.time()
                    set_time = True
                word = self.ser.read(4)
                if verb:
                    print("Received:", word.hex())
                
                curr_misal = 0
                for i in range(4):
                    if word.hex() == 'deadbeef':
                        break
                    word = word[3:4] + word[0:3]
                    curr_misal += 1

                if curr_misal == 4:
                    print("ERR: extraneous", word.hex())
                else:
                    mis_align = curr_misal
                    # Fix misalignment:
                    self.ser.read(4-mis_align)
                    break

        if verb:
            print("Asserted misalignment =", mis_align, "dropped", 4-mis_align, "to correct")
            print("Ready to receive data")

        # Send 5 to make sure FPGA catches 1
        for i in range(5):
            self.ser.write(bytes([0x0C]*4))

        self.ser.flush()

        if verb:
            print("Sent the 1st OK (0C), waiting for valid messages...") 

        while True:
            if self.ser.in_waiting >= 4:
                word = self.ser.read(4)
                n = self.bytes_to_num(word)
                msb = self.get_bit(n, 31)
                if msb:
                    if verb:
                        print("Extraneous message recvd", word.hex())
                    continue
                
                x_ix = self.get_bit_slice(n, 29, 23)
                y_ix = self.get_bit_slice(n, 22, 16)
                data = self.get_bit_slice(n, 15, 0)
                if verb:
                    print(f"Received result ({word.hex()}) for posn ({x_ix}, {y_ix}), data = {data}")

                if vector_mode:
                    result[y_ix] = data
                else:
                    result[y_ix][x_ix] = data

                if not self.has_nones(result, vector_mode):
                    if verb:
                        print("Finished receiving, sending 2nd OK (1C)")
                    self.ser.write(bytes([0x1C]*4))
                    self.ser.flush()
                    return (result, ret_time)

    def has_nones(self, res, vector_mode):
        if vector_mode:
            for e in res:
                if e is None:
                    return True
        else:
            for row in res:
                for e in row:
                    if e is None:
                        return True
        return False

    def bytes_to_num(self,word):
        # assuming word is 4 bytes
        return word[3] + (word[2] << 8) + (word[1] << 16) + (word[0] << 24)

    def get_bit(self, n, ix):
        # gets bit in n using verilog indexing (i.e. lsb has ix = 0)
        return (n & (1<<ix))>>ix
    
    def get_bit_slice(self, n, hi, lo):
        # get slice of bits using verilog indexing
        return (n & ((1<<(hi+1))-1)&~((1<<lo)-1))>>lo
 

    def write_data(self, acts, weights, vector_mode=1, verb=0, max_resends=3):
        if verb:
            print("Beginning alignment procedure for writing")

        while True:
            msg = b'\xde\xad\xbe\xef'
            self.ser.write(4*msg[::-1])   # little end
            self.ser.flush()
            if verb:
                print("Sent", msg.hex())
            time.sleep(0.01)

            if self.ser.in_waiting >= 4:
                word = self.ser.read(4)
                if verb:
                    print("Received:", word.hex())
                if word.hex() == '0c0c0c0c':
                    if verb:
                        print("Received 1st acknowledgement")
                    magic = b'\xda\x22\x1d\x06'
                    self.ser.write(magic[::-1])
                    self.ser.flush()
                    if verb:
                        print("Sent magic", magic.hex())
                    break

        if verb:
            print("Beginning to send data payload")

        weight_data = self.pack_matrix(weights)

        if vector_mode:
            act_data = self.pack_vector(acts)
        else:
            act_data = self.pack_matrix(acts, is_weights=0) 

        self.ser.write(weight_data)
        self.ser.write(act_data)
        self.ser.flush()

        if verb:
            print("Sent two packs")
        time.sleep(0.01)
        last_contact = time.time()
        num_times = 1
        while True:
            if self.ser.in_waiting >= 4:
                word = self.ser.read(4)
                if word.hex() == '1c1c1c1c':
                    if verb:
                        print("\nReceived 2nd acknowledgment, stopping sending")
                    return (True, time.time())

            if time.time() - last_contact > 0.1:
                if num_times == max_resends:
                    if verb:
                        print("Timeout, max resends reached. Abort.")
                    return (False, 0)
                if verb:
                    print("Timeout... resending")
                self.ser.write(weight_data)
                self.ser.write(act_data)
                self.ser.flush() 
                time.sleep(0.01)
                num_times += 1
        
    def pack_matrix(self, mat, is_weights=1):
        ret = b""
        for y_ix in range(self.N):
            for x_ix in range(self.N):
                data = mat[x_ix][y_ix]
                data_frame = self.build_dataframe(0,is_weights,x_ix,y_ix,data)
                ret += data_frame
        return ret

    def pack_vector(self, vec):
        ret = b""
        for y_ix in range(self.N):
            data = vec[y_ix]
            data_frame = self.build_dataframe(0,0,0,y_ix,data)
            ret += data_frame
        return ret

    def build_dataframe(self, msb, weight, xix, yix, data):
        xix  = self.get_bit_slice(xix,   6, 0)
        yix  = self.get_bit_slice(yix,   6, 0)
        data = self.get_bit_slice(data, 15, 0) 
        # left shift by k => leave k zeros to the right
        ret = (msb << 31) + (weight << 30) + (xix << 23) + (yix << 16) + data
        # guarantee its a 32 bit number
        # and return bytes object
        return self.get_bit_slice(ret, 31, 0).to_bytes(4, byteorder='little')

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            print(f"\nClosed port {self.port}") 
