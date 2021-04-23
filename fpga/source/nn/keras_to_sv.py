# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL POTENTIAL VENTURES LTD BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

"""
Keras to System Verilog Neural Net Parser

This script transforms a Keras fully connected network model into several files
required for the parameteric generation of a system verilog IP core nn developed
by Edge Analytics, Inc.
"""

import os
import argparse

from string import Template
from fixedpoint import FixedPoint
from tensorflow import keras
from typing import List


def parse_keras_model(keras_h5_path: str, output_directory: str, param_m: int, param_n: int):
    """ Parse Keras fully connected network model and generate the SV required files """

    if not os.path.exists(output_directory):
        os.makedirs(output_directory)

    model = keras.models.load_model(keras_h5_path)
    biases = open(os.path.join(output_directory, "biases.mif"), 'w')
    weights = open(os.path.join(output_directory, "weights.mif"), 'w')

    num_inputs = model.input_shape[1]
    num_outputs = model.output_shape[1]
    num_layers = len(model.layers) + 1 # Consider the input layer

    if max(num_inputs, num_outputs, num_layers) > 255:
        raise ValueError(
            "Model is limited to a maximum dimension of 255 for inputs, outputs and hidden layers")

    max_abs_bias = 0
    max_abs_weight = 0
    num_weights = 0
    num_biases = 0
    neurons_per_layer = [num_inputs]

    for layer in model.layers:
        np_layer_weights = layer.weights[0].numpy()
        np_layer_biases = layer.weights[1].numpy()
        neurons_per_layer.append(np_layer_biases.shape[0])
        for layer_weights in np_layer_weights:
            for weight in layer_weights:
                max_abs_weight = _update_max(curr_val=weight, max_val=max_abs_weight)
                weights.write(
                    str(FixedPoint(weight, signed=True, m=param_m, n=param_n, str_base=2)) + '\n')
                num_weights += 1         
        for bias in np_layer_biases:
            max_abs_bias = _update_max(curr_val=bias, max_val=max_abs_bias)
            biases.write(
                str(FixedPoint(bias, signed=True, m=param_m, n=param_n, str_base=2)) + '\n')
            num_biases += 1
    weights.close()
    biases.close()

    max_parameter_range = 2 ** (param_m -1) - (1 / (2 ** param_n))
    if max_abs_weight > max_parameter_range or max_abs_bias > max_parameter_range:
        raise ValueError(f"Parameter value exceeds {max_parameter_range}")
    
    sv_template = _get_nn_pkg_template()
    sv_pkg_str = sv_template.substitute(
        num_weights=str(num_weights),
        num_biases=str(num_biases),
        param_width=str(param_m + param_n),
        param_q_int=str(param_m),
        num_layers=str(num_layers),
        max_layer_depth=str(max(neurons_per_layer)),
        nn_inputs=str(num_inputs),
        nn_outputs=str(num_outputs),
        neurons_per_layer=_generate_nn_layers_sv_entry(neurons_per_layer)
        )
    sv_pkg = open(os.path.join(output_directory, "nn_pkg.sv"), 'w')
    sv_pkg.write(sv_pkg_str)
    sv_pkg.close()
    
    print("\n")
    print("=================== SUMMARY ===================")
    print(f"num weights {num_weights} requiring {num_weights*2/1000} kB")
    print(f"num biases {num_biases} requiring {num_biases*2/1000} kB")
    print(f"maximum weight parameter is {max_abs_weight}")
    print(f"maximum bias parameter is {max_abs_bias}")
    print(f"maximum parameter range is {max_parameter_range}")
    print(f"num inputs {num_inputs}")
    print(f"num outputs {num_outputs}")
    print(f"num neurons per layer {neurons_per_layer}")
    print(f'num layers {num_layers}')
    print(f"max layer depth {max(neurons_per_layer)}")


def _get_nn_pkg_template() -> Template:
    nn_pkg_template = """
package nn_pkg;
// NN package for parameters that define a given mlp model
// The model is restricted to less than 256 inputs, 256 outputs and 256 layers 

// NN general parameters dependent on model
localparam NUM_WEIGHTS = $num_weights;
localparam NUM_BIASES = $num_biases;
localparam INPUT_DATA_WIDTH = 32;
localparam OUTPUT_DATA_WIDTH = 32;
localparam OUTPUT_Q_INT = 16;
localparam OUTPUT_Q_FRAC = OUTPUT_DATA_WIDTH - OUTPUT_Q_INT;
localparam PARAM_WIDTH = $param_width;
localparam PARAM_Q_INT = $param_q_int;
localparam PARAM_Q_FRAC = PARAM_WIDTH - PARAM_Q_INT;

localparam NUM_LAYERS = $num_layers;
localparam MAX_LAYER_DEPTH = $max_layer_depth;
localparam NN_INPUTS = $nn_inputs;
localparam NN_OUTPUTS = $nn_outputs;

localparam logic [7:0] NEURONS_PER_LAYER [NUM_LAYERS] = '{
$neurons_per_layer
};

// TODO add function for relu
function automatic logic signed[OUTPUT_DATA_WIDTH-1:0] relu(input logic signed[OUTPUT_DATA_WIDTH-1:0] x);
    return x < 0 ? '0: x;
endfunction

endpackage: nn_pkg
    """
    return Template(nn_pkg_template)

def _generate_nn_layers_sv_entry(neurons_per_layer: List[int]) -> str:
    sv_nn_layers = ""
    num_layers = len(neurons_per_layer)
    for i, num_neurons in enumerate(neurons_per_layer):
        entry_delimiter = ",\n" if i < num_layers - 1 else ""
        sv_nn_layers += "\t8\'d" + str(num_neurons) + entry_delimiter
    return sv_nn_layers

def _update_max(curr_val, max_val) -> int:
    abs_current = abs(curr_val)
    if abs_current > max_val:
        return abs_current
    else:
        return max_val


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Keras to System Verilog code generator.")
    parser.add_argument("-input", "-i", required=True,
                        help="Path to the .h5 keras fully connected model")
    parser.add_argument("-output", "-o", required=True,
                        help="Path to export the generated sv files")
    parser.add_argument("--m", default=2,
                        help="Number of integer bits in the signed fixed point parameters")
    parser.add_argument("--n", default=14,
                        help="Number of fractional bits in the signed fixed point parameters")
    args = parser.parse_args()

    parse_keras_model(
        keras_h5_path=args.input,
        output_directory=args.output,
        param_m=args.m,
        param_n=args.n
    )