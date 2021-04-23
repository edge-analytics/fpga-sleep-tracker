from fixedpoint import FixedPoint
from tensorflow import keras
import numpy as np
from matplotlib import pyplot as plt

DEBUG_FPGA_CAPTURE = True

model = keras.models.load_model('../../../models/mnist_40_model.h5')

# Class 0 - digit zero example input
mnist_test_set = np.load("../../../models/test_set.npz")
test_digits = mnist_test_set['x']
test_labels = mnist_test_set['y']
x = test_digits[0]

def relu(x):
    return x * (x > 0)

internal_calcs = []
for i, layer in enumerate(model.layers):
    weights = np.transpose(layer.weights[0].numpy())
    biases = layer.weights[1].numpy()
    print(f"index {i} bias\n {biases} \n")
    acc = np.zeros((weights.shape[0],))
    for c in range(weights.shape[1]):
        acc = acc + x[c] * weights[:,c]
        internal_calcs.append(acc)
    internal_calcs.append((weights.shape[0],)) # Next layer is zeroed out with bias application
    y = relu(np.matmul(weights, x) + biases)
    if i == 1:
        print(f"second layer biases \n {biases}")
        print(f"second layer sums \n {acc}")
        print(f"second layer output \n {relu(acc+biases)}")
    x = y
#print('\n' + str(y))
if DEBUG_FPGA_CAPTURE:
    x_sv = np.load("mem.npz")['x']
    # for i in range(64):
    #     offset = i*40
    #     error = x_sv[offset:offset+40]- internal_calcs[i]
    #     plt.plot(x_sv[offset:offset+40] - internal_calcs[i])
    #     if i == 2:
    #         print(f"Error threshold violated at index {i}")
    #         plt.plot(x_sv[offset:offset+40] - internal_calcs[i])
    #         print(f"found: \n {x_sv[offset:offset+40]}")
    #         print(f"expected: \n {internal_calcs[i]}")
    #         print(f"weights: \n {model.layers[0].weights[0].numpy()[i]}")
    #         #break
    starting_offset = 65*40 #+ 41*20# 64weights + 1bias + 40weights + 1bias
    for i in range(40):
        offset = i*20 + starting_offset
        error = x_sv[offset:offset+20] - internal_calcs[65+i]
        plt.plot(x_sv[offset:offset+20] - internal_calcs[65+i])
        print(f"found: \n {x_sv[offset:offset+20]}")
        print(f"expected: \n {internal_calcs[65+i]}")
    plt.show()
# Mnist Class 0 expected example assoicated with input above
#y_expected = [13.099907, 0., 0., 0., 0., 4.661643, 0. ,0.32301515, 0. ,1.0999551 ]
#assert np.allclose(y, y_expected)
print(f"Expected classification {y}")
#print(x_sv[63*40:63*40+40])