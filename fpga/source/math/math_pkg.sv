package math_pkg;

function automatic logic [7:0] abs_i8(input logic signed[7:0] x);
    return x < 0 ? -x: x;
endfunction

endpackage: math_pkg