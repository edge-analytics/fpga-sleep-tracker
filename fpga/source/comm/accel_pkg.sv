package accel_pkg;

typedef struct packed{
    logic signed[15:0] x;
    logic signed[15:0] y;
    logic signed[15:0] z;
    logic signed[15:0] v;
} accel_data_t;

endpackage: accel_pkg