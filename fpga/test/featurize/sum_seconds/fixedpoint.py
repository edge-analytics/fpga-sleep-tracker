import numpy as np

def bin2(val, width):
        if val < 0:
            return bin((1 << width) + val)[2::]
        else:
            return bin(val)[2::].zfill(width)

class FixedPoint:
    # The python fixedpoint library is only supported in python3.8
    # Since modelsim requires 32 bit python this class was required

    def __init__(self, val, int_bits=8,fract_bits=8):
        self.int_bits = int_bits
        self.fract_bits = fract_bits
        self.bit_width = int_bits + fract_bits
        self.fxp = self.convert_to_fxp(val)

    def convert_to_fxp(self, val):
        val_type = type(val)
        if(val_type == float or val_type == np.float64):
            return bin2(int(val*(2**self.fract_bits)), self.bit_width)
        elif (val_type == str):
            if len(val) != self.bit_width:
                raise Exception(f"Binstr len {len(val)} != {self.bit_width}")
            return val
        else:
            raise Exception(f"FXP conversion not implemented for {val_type}")

    def __float__(self):
        bin_vec = [int(b == '1') for b in self.fxp]
        int_val = 0
        for i, b in enumerate(bin_vec):
            int_val += b * 2 ** (self.bit_width - i - 1)
        if bin_vec[0]:
            int_val -= 2**self.bit_width
        
        return float(int_val / 2**self.fract_bits)

    def __add__(self, v):
        return FixedPoint(float(self) + float(v))
    
    def __sub__(self, v):
        return FixedPoint(float(self) - float(v))
    
    def __mul__(self, v):
        return FixedPoint(float(self) * float(v))
        
    def __str__(self):
        return self.fxp
    def __repr__(self):
        return f"Q{self.int_bits}.{self.fract_bits} bin_str: {self.fxp}"

if __name__ == "__main__":
    x = FixedPoint(-0.5, 1, 7)
    print(float(x))