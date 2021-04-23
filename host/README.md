# Rust Host Communication and FPGA Driver

A library and CLI tool for communicating with the FPGA sleep app.

## Getting Started

### Installing Rust

Using `rustup` is recommended via `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` in your terminal.

### Installing CLI Locally

From the repo home directory, run `cargo install --path .` This will install this repo as the CLI command `nnfpga` in the user's `.cargo/bin` directory.

## Example CLI Usage

`cargo run -- unbounded > out.txt`

`cargo run -- bounded -t 60 > out.txt`

(With local binary install)

`nnfpga unbounded > out.txt`

`nnfpga bounded -t 60 > out.txt`