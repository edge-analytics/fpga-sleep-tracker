use host_comm::take_fpga_session;
use std::io::{Read, Write};
use structopt::StructOpt;

fn wait_for_input() {
    let mut stdin = std::io::stdin();
    let mut stderr = std::io::stderr();

    write!(stderr, "Hit enter to conclude the acquisition...").unwrap();
    stderr.flush().unwrap();
    let _ = stdin.read(&mut [0u8]).unwrap();
}

/// CLI representation.
#[derive(StructOpt)]
#[structopt(name = "sleep", about = "FPGA sleep app CLI driver.")]
enum Opt {
    /// Acquire data for an unbounded amount of time (hit enter to stop).
    Unbounded,
    /// Acquire data for the specified number of seconds.
    Bounded {
        /// Time to gather data in seconds.
        #[structopt(short = "t", long = "time", default_value = "60")]
        time: u64,
    },
}

fn main() -> anyhow::Result<()> {
    let opt = Opt::from_args();

    let mut sesh = take_fpga_session();
    sesh.stop()?;
    std::thread::sleep(std::time::Duration::from_millis(100));

    match opt {
        Opt::Unbounded => {
            sesh.start()?;
            wait_for_input();
            sesh.stop()?;
        }
        Opt::Bounded { time } => {
            sesh.start()?;
            std::thread::sleep(std::time::Duration::from_secs(time));
            sesh.stop()?;
        }
    }
    let output = sesh.read_fifo(128, 0)?;
    for v in output {
        println!("{}, {}", v.counts, v.sleep_wake_class);
    }
    Ok(())
}
