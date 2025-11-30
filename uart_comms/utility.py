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
        while True:
            word = self.ser.read(4)
            if word:
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
        print("Sent the 'OC' (ok), waiting for valid messages...")
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
                    print("Received a message!", word.hex())


    def bytes_to_num(self,word):
        # assuming word is 4 bytes
        return word[3] + (word[2] << 8) + (word[1] << 16) + (word[0] << 24)

    def get_bit(self, n, ix):
        # gets bit in n using verilog indexing (i.e. lsb has ix = 0)
        return (n & (1<<ix))>>ix

    def write_data(self, data):
        for val in data:
            self.ser.write(bytes([val]))
            print(f"Sent {hex(val)}")
            time.sleep(0.01)

    def close(self):
        if self.ser and self.ser.is_open:
            self.ser.close()
            print(f"\nClosed port {self.port}")
