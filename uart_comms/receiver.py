import serial
import time

SERIAL_PORT = 'COM59' 
BAUD_RATE = 9600
TIMEOUT = 1 
try:
    ser = serial.Serial(
        port=SERIAL_PORT,
        baudrate=BAUD_RATE,
        parity=serial.PARITY_EVEN, 
        stopbits=serial.STOPBITS_ONE,
        bytesize=serial.EIGHTBITS,
        timeout=TIMEOUT
    )
    time.sleep(2) # Give the connection a moment to establish
    ser.flushInput() # Clear the buffer of any old data
    print(f"Connected to {SERIAL_PORT} at {BAUD_RATE} baud rate.")
    print("Reading data... Press Ctrl+C to stop.")

    while True:
        byte_read = ser.read(1)
        
        if byte_read:
            n = byte_read[0]
            print("Read:", n, hex(n), bin(n))

except serial.SerialException as e:
    print(f"Error opening serial port: {e}")
except KeyboardInterrupt:
    print("\nProgram interrupted by user. Closing port.")
except Exception as e:
    print(f"An unexpected error occurred: {e}")
finally:
    if 'ser' in locals() and ser.isOpen():
        ser.close()
        print("Serial port closed.")
