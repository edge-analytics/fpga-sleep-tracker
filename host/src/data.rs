//! Data types and conversions.

use fixed::types::{I16F16, I1F7};
use serde::{Deserialize, Serialize};

use crate::{error::FpgaDriverError, traits::Data, FpgaDriverResult};

/// Number of input elements for sleep model.
pub const INPUT_NELEM_SLEEP: usize = 3;
/// Number of output elements for sleep model.
pub const OUTPUT_NELEM_SLEEP: usize = 2;

/// Sleep tracker application features.
#[derive(Debug, Deserialize)]
pub struct SleepFeatures {
    pub activity_count: f32,
    pub heart_rate: f32,
    pub sleep_cosine: f32,
}
impl From<SleepFeatures> for [I1F7; INPUT_NELEM_SLEEP] {
    fn from(features: SleepFeatures) -> [I1F7; INPUT_NELEM_SLEEP] {
        [
            I1F7::from_num(features.activity_count),
            I1F7::from_num(features.heart_rate),
            I1F7::from_num(features.sleep_cosine),
        ]
    }
}

/// Sleep tracker application output.
#[derive(Debug, Serialize)]
pub struct SleepTrackerOutput {
    pub counts: u8,
    pub sleep_wake_class: u8,
}
impl From<[u8; OUTPUT_NELEM_SLEEP]> for SleepTrackerOutput {
    fn from(array: [u8; OUTPUT_NELEM_SLEEP]) -> SleepTrackerOutput {
        SleepTrackerOutput {
            counts: array[0],
            sleep_wake_class: array[1],
        }
    }
}
pub(crate) struct SleepTrackerOutputVec(Vec<SleepTrackerOutput>);
impl SleepTrackerOutputVec {
    pub fn into_vec(self) -> Vec<SleepTrackerOutput> {
        self.0
    }
}
impl From<Vec<u8>> for SleepTrackerOutputVec {
    fn from(v: Vec<u8>) -> SleepTrackerOutputVec {
        let mut out = Vec::with_capacity(v.len() / 2);
        for data in v.chunks_exact(2) {
            out.push(SleepTrackerOutput {
                counts: data[0],
                sleep_wake_class: data[1],
            });
        }
        SleepTrackerOutputVec(out)
    }
}

macro_rules! impl_data_on_primitives {
    ($([$t:ty => $N:expr]),*) => {
        $(
            impl Data for $t {
                fn from_le_bytes(bytes: &[u8]) -> FpgaDriverResult<Self> {
                    if bytes.len() != std::mem::size_of::<Self>() {
                        Err(FpgaDriverError::WrongNumBytesToCastToConcreteType {
                            ty: stringify!($t),
                            expected_bytes: std::mem::size_of::<Self>(),
                            encountered_bytes: bytes.len(),
                        })
                    } else {
                        let mut byte_arr: [u8; $N] = [0; $N];
                        for idx in 0..$N {
                            byte_arr[idx] = bytes[idx]
                        }
                        Ok(<$t>::from_le_bytes(byte_arr))
                    }
                }
                fn to_le_bytes(self) -> Box<[u8]> {
                    Box::new(self.to_le_bytes())
                }
            }
        )*
    };
}

impl_data_on_primitives! {
    [u8 => 1],
    [u16 => 2],
    [u32 => 4],
    [u64 => 8],
    [i8 => 1],
    [i16 => 2],
    [i32 => 4],
    [i64 => 8],
    [I1F7 => 1],
    [I16F16 => 4]
}
impl<T: Data + Copy + Default, const N: usize> Data for [T; N] {
    fn from_le_bytes(bytes: &[u8]) -> FpgaDriverResult<Self> {
        if bytes.len() != std::mem::size_of::<T>() * N {
            Err(FpgaDriverError::WrongNumBytesToCastToConcreteType {
                ty: "[T; N]",
                expected_bytes: std::mem::size_of::<T>() * N,
                encountered_bytes: bytes.len(),
            })
        } else {
            let mut arr = [T::default(); N];
            for (chunk, v) in bytes
                .chunks_exact(std::mem::size_of::<T>())
                .zip(arr.iter_mut())
            {
                *v = T::from_le_bytes(chunk)?;
            }
            Ok(arr)
        }
    }
    fn to_le_bytes(self) -> Box<[u8]> {
        let mut vec = Vec::with_capacity(std::mem::size_of::<T>() * N);
        for v in std::array::IntoIter::new(self) {
            vec.extend_from_slice(&v.to_le_bytes());
        }
        vec.into_boxed_slice()
    }
}
