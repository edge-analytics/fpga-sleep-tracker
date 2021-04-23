def bin2(val, width):
        if val < 0:
            return bin((1 << width) + val)[2::]
        else:
            return bin(val)[2::].zfill(width)