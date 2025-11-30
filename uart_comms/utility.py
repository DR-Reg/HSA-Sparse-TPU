import serial
import time

# TODO: variable bytesize
def read_data(port, result_size, bytesize=serial.EIGHTBITS, baudrate=9600, timeout=1, verb=0):
    try:
        ser = serial.Serial(
            port = port,
            baudrate=baudrate,
            parity=serial.PARITY_EVEN,
            stopbits=serial.STOPBITS_ONE,
            bytesize=bytesize,
            timeout=timeout
        )
        
        # Allow for connection to stabilise
        time.sleep(2)
        ser.flushInput()

        if verb:
            print(f"Connected to {port} at {baudrate} baud")
            print("Listening...")

        result = [None for i in range(result_size)]
        while True:
            byte = ser.read(1)
            if byte:
                n = byte[0]
                if verb:
                    print("Received:", bin(n))
                # Extract result index:
                res_ix = (n & 0xf0) >> 4
                res_val = n & 0x0f
                if res_ix >= result_size:
                    print("Received corrupted data:", n, hex(n), bin(n))
                result[res_ix] = res_val

            # Once we've read all results:
            if len([e for e in result if e is None]) == 0:
                return result
    except KeyboardInterrupt:
        print("Closing...")
    except Exception as e:
        print("Exception:", e)
    # Close even if exception:
    finally:
        if 'ser' in locals() and ser.isOpen():
            ser.close()
            if verb:
                print(f"Closed port {port}")

