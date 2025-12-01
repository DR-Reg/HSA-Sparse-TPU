import serial
import time

# TODO: variable bytesize
class SerialPort:
    def __init__(self, port, bytesize=serial.EIGHTBITS, baudrate=9600, timeout=1):
        self.ser = serial.Serial(
            port = port,
            baudrate=baudrate,
            parity=serial.PARITY_EVEN,
            stopbits=serial.STOPBITS_ONE,
            bytesize=bytesize,
            timeout=timeout
        )
        self.bytesize = bytesize
        self.baudrate = baudrate
        self.timeout = timeout
        self.port = port
       
        # Allow for connection to stabilise
        time.sleep(2)
        
        if self.ser.isOpen():
            self.ser.flushInput()
            self.ser.flushOutput()
            print(f"Connected to {port} at {baudrate} baud")
            print("Listening...") 
        else:
            raise Exception(f"Unable to open {port}")

    def read_data(self, result_size, verb=0):
        result = [None for i in range(result_size)]

        
        # Establish alignment by reading DEADBEEF
        sat_counter = 0     # make sure by receiving it 10 times
        mis_align = 0       # stores most recent misalignment delta
        ret_time = 0        # should return when time when first deadbeef received
        set_time = False    # boolean for once we have set above time
        while True:
            if self.ser.in_waiting >= 4:
                if not set_time:
                    ret_time = time.time()
                    set_time = True
                word = self.ser.read(4)
                if verb:
                    print("Received:", word.hex())
                # Check all possible misalignments
                curr_misal = 0
                for i in range(4):
                    if word.hex() == 'deadbeef':
                        break
                    word = word[3:4] + word[0:3]
                    curr_misal += 1
                if curr_misal == 4:         # no misalignments match, reset sat counter
                    sat_counter = 0
                elif sat_counter == 0:
                    mis_align = curr_misal
                    sat_counter += 1
                elif sat_counter < 10:
                    # unmatching misalignment, reset counter
                    if mis_align != curr_misal:
                        sat_counter = 0
                    else:
                        sat_counter += 1
                else:   # ok, we have detected the misalignment
                    # so account for it by reading 4 - misalignment
                    # since misalignment is no. times had to circular
                    # shift bytes to the right if i did this e.g.
                    # 3 times, then that means we are one byte off from
                    # the start
                    self.ser.read(4 - mis_align)
                    break
        print("Asserted misalignment =", mis_align, "dropped", 4-mis_align, "to correct")
        print("Ready to receive data")
        self.ser.write(bytes([0x0C]*4))
        print("Sent the 1st OK (0C), waiting for valid messages...")
        while True:
            word = self.ser.read(4)
            if word:
                # valid messages have msb = 0
                n = self.bytes_to_num(word)
                msb = self.get_bit(n, 31)
                if msb:
                    if n != 0xdeadbeef:
                        print("Extraneous non-message data after alignment:", word.hex())
                    else:
                        if verb:
                            print("Extra deadbeef receieved, still waiting for messages...")
                else:
                    x_ix = self.get_bit_slice(n, 29, 23)
                    y_ix = self.get_bit_slice(n, 22, 16)
                    data = self.get_bit_slice(n, 15, 0)
                    if verb:
                        print(f"Received result ({word.hex()}) for posn ({x_ix}, {y_ix}), data = {data}")

                    result[y_ix] = data
            if len([e for e in result if e is None]) == 0:
                print("Finished receiving, sending 2nd OK (1C)")
                self.ser.write(bytes([0x1C]*4))
                return (result, ret_time)

    def bytes_to_num(self,word):
        # assuming word is 4 bytes
        return word[3] + (word[2] << 8) + (word[1] << 16) + (word[0] << 24)

    def get_bit(self, n, ix):
        # gets bit in n using verilog indexing (i.e. lsb has ix = 0)
        return (n & (1<<ix))>>ix
    
    def get_bit_slice(self, n, hi, lo):
        # get slice of bits using verilog indexing
        return (n & ((1<<(hi+1))-1)&~((1<<lo)-1))>>lo

    def write_data(self, acts, weights, SIZE):
        print("Preparing to write data, beginning alignment procedure")
        while True:
            msg = b'\xde\xad\xbe\xef'
            self.ser.write(msg[::-1])   # little end
            print("Sent", msg.hex())
            if self.ser.in_waiting >= 4:
                word = self.ser.read(4)
                if word.hex() == '0c0c0c0c':
                    print("Received 1st acknowledgement")
                    magic = b'\xda\x22\x1d\x06'
                    self.ser.write(magic[::-1])
                    print("Sent magic", magic.hex())
                    break
        print("Beginning to send data payload")
        sending_weights = 0
        x_ix = y_ix = 0
        # TODO: matrixify the acts!
        while True:
            data = weights[y_ix][x_ix] if sending_weights else acts[y_ix]
            data_frame = self.build_dataframe(0,sending_weights,x_ix,y_ix,data)
            self.ser.write(data_frame)
            nd = int.from_bytes(data_frame, 'little', signed=False)
            dx_ix = self.get_bit_slice(nd, 29, 23) 
            dy_ix = self.get_bit_slice(nd, 22, 16) 
            dsending_weights = self.get_bit(nd, 30)
            ddata = self.get_bit_slice(nd, 3, 0)
            print(f"Sent data frame (x={dx_ix}, y={dy_ix}, a/w={dsending_weights}, data={ddata}) :", data_frame.hex())

            # update the indeces appropriately
            x_ix += 1
            if x_ix == SIZE or (x_ix == 1 and sending_weights == 0):
                y_ix += 1
                x_ix = 0
                if y_ix == SIZE:
                    sending_weights += 1
                    y_ix = 0
                    if sending_weights == 2:
                        sending_weights = 0

            # Check for 2nd acknowledgement, stop sending
            if self.ser.in_waiting >= 4:
                word = self.ser.read(4)
                if word.hex() == '1c1c1c1c':
                    print("Received 2nd acknowledgment, stopping sending")
                    return time.time()  ## return time we have received ack

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
