use fixed::types::I1F7;
use host_comm::session::{INPUT_BASE_ADDRESS, OUTPUT_BASE_ADDRESS};
use host_comm::take_fpga_session;

fn main() -> anyhow::Result<()> {
    let mut sesh = take_fpga_session();

    let digit_fxp = vec![
        -0.5, -0.5, -0.0625, 0.5, 0.5, 0.375, -0.5, -0.5, -0.5, -0.5, 0.5, 0.25, 0.125, 0.4375,
        -0.4375, -0.5, -0.5, -0.5, 0.125, -0.25, 0.5, 0.125, -0.5, -0.5, -0.5, -0.5, -0.5, 0.0625,
        0.5, 0.1875, -0.4375, -0.5, -0.5, -0.5, -0.5, -0.5, -0.0625, 0.5, 0., -0.5, -0.5, -0.5,
        -0.5, -0.5, -0.5, 0.5, -0.0625, -0.5, -0.5, -0.5, 0., -0.25, 0.125, 0.4375, -0.375, -0.5,
        -0.5, -0.5, 0.25, 0.5, 0.5, -0.125, -0.5, -0.5,
    ]
    .into_iter()
    .map(I1F7::from_num)
    .collect::<Vec<I1F7>>();

    // Clear state in command and status registers.
    sesh.stop()?;
    sesh.clear_status()?;
    println!("cmd initial state is {}", sesh.read_command_register()?);
    println!("status is {}", sesh.read_status_register()?);

    // Write in pixel data.
    for (idx, &pixel) in digit_fxp.iter().enumerate() {
        sesh.write_data(pixel, INPUT_BASE_ADDRESS + idx as u16)?;
    }
    std::thread::sleep(std::time::Duration::from_millis(100));

    // Do the NN calculation on the FPGA and wait until done.
    sesh.start()?;
    while !sesh.calc_is_done()? {}
    println!("status is {}", sesh.read_status_register()?);

    // Read the outputs and write to `stdout`.
    let num_outputs = 10;
    for idx in 0..num_outputs {
        let output =
            sesh.read_data::<u32>(OUTPUT_BASE_ADDRESS + (idx * 4) as u16)? as f32 / 65535_f32;
        println!("Output value {} is {}", idx, output);
    }
    println!("cmd final state is {}", sesh.read_command_register()?);

    Ok(())
}
