use host_comm::take_fpga_session;

fn main() -> anyhow::Result<()> {
    let mut sesh = take_fpga_session();

    // Clear state in command and status registers.
    sesh.stop()?;
    println!(
        "`command` initial state is {}",
        sesh.read_command_register()?
    );
    println!("`status` is {}", sesh.read_status_register()?);

    // Start a data acquisition session.
    sesh.start()?;
    std::thread::sleep(std::time::Duration::from_secs(60));

    // Stop data acquisition after 60 seconds.
    sesh.stop()?;
    let output_vec = sesh.read_fifo(4, 0)?;

    // Print output data from the FPGA.
    println!("`output_vec`: {:?}", &output_vec);

    Ok(())
}
