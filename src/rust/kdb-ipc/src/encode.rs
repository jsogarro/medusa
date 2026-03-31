//! kdb+ IPC wire format encoder
//!
//! Encodes K objects into the binary IPC protocol.
//! See: https://code.kx.com/q/basics/ipc/

use crate::error::{KdbError, Result};
use crate::types::KObject;
use byteorder::{LittleEndian, WriteBytesExt};
use std::io::Write;

/// IPC message types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum MessageType {
    /// Async message (no response expected)
    Async = 0,
    /// Sync message (response expected)
    Sync = 1,
    /// Response message
    Response = 2,
}

/// Encoder for kdb+ IPC messages
pub struct Encoder {
    buffer: Vec<u8>,
}

impl Encoder {
    /// Create a new encoder
    pub fn new() -> Self {
        Self {
            buffer: Vec::new(),
        }
    }

    /// Encode an async message (fire-and-forget)
    pub fn encode_async(&mut self, obj: &KObject) -> Result<Vec<u8>> {
        self.encode_message(MessageType::Async, obj)
    }

    /// Encode a sync message (request-response)
    pub fn encode_sync(&mut self, obj: &KObject) -> Result<Vec<u8>> {
        self.encode_message(MessageType::Sync, obj)
    }

    /// Encode a complete message with header
    fn encode_message(&mut self, msg_type: MessageType, obj: &KObject) -> Result<Vec<u8>> {
        self.buffer.clear();

        // Reserve space for header (8 bytes)
        self.buffer.resize(8, 0);

        // Encode the object payload
        self.encode_object(obj)?;

        // Write header
        let total_len = self.buffer.len() as u32;
        self.buffer[0] = 1; // little-endian
        self.buffer[1] = msg_type as u8;
        self.buffer[2] = 0; // no compression
        self.buffer[3] = 0; // reserved
        self.buffer[4..8].copy_from_slice(&total_len.to_le_bytes());

        Ok(self.buffer.clone())
    }

    /// Write list length with overflow check
    fn write_list_length(&mut self, len: usize) -> Result<()> {
        let len_i32 = i32::try_from(len).map_err(|_| {
            KdbError::EncodingError(format!(
                "List length {} exceeds maximum i32::MAX",
                len
            ))
        })?;
        self.buffer.write_i32::<LittleEndian>(len_i32)?;
        Ok(())
    }

    /// Encode a K object
    pub fn encode_object(&mut self, obj: &KObject) -> Result<()> {
        match obj {
            // Atoms
            KObject::Bool(v) => self.encode_bool_atom(*v),
            KObject::Byte(v) => self.encode_byte_atom(*v),
            KObject::Short(v) => self.encode_short_atom(*v),
            KObject::Int(v) => self.encode_int_atom(*v),
            KObject::Long(v) => self.encode_long_atom(*v),
            KObject::Real(v) => self.encode_real_atom(*v),
            KObject::Float(v) => self.encode_float_atom(*v),
            KObject::Char(v) => self.encode_char_atom(*v),
            KObject::Symbol(v) => self.encode_symbol_atom(v),
            KObject::Timestamp(v) => self.encode_timestamp_atom(*v),
            KObject::Date(v) => self.encode_date_atom(*v),
            KObject::DateTime(v) => self.encode_datetime_atom(*v),
            KObject::Timespan(v) => self.encode_timespan_atom(*v),
            KObject::Time(v) => self.encode_time_atom(*v),

            // Lists
            KObject::BoolList(v) => self.encode_bool_list(v),
            KObject::ByteList(v) => self.encode_byte_list(v),
            KObject::ShortList(v) => self.encode_short_list(v),
            KObject::IntList(v) => self.encode_int_list(v),
            KObject::LongList(v) => self.encode_long_list(v),
            KObject::RealList(v) => self.encode_real_list(v),
            KObject::FloatList(v) => self.encode_float_list(v),
            KObject::CharList(v) => self.encode_char_list(v),
            KObject::SymbolList(v) => self.encode_symbol_list(v),
            KObject::TimestampList(v) => self.encode_timestamp_list(v),
            KObject::DateList(v) => self.encode_date_list(v),
            KObject::DateTimeList(v) => self.encode_datetime_list(v),
            KObject::TimespanList(v) => self.encode_timespan_list(v),
            KObject::TimeList(v) => self.encode_time_list(v),

            // Composites
            KObject::MixedList(v) => self.encode_mixed_list(v),
            KObject::Dict(keys, values) => self.encode_dict(keys, values),
            KObject::Table(cols, data) => self.encode_table(cols, data),
            KObject::Error(msg) => self.encode_error(msg),

            _ => Err(KdbError::EncodingError(format!(
                "Unsupported type: {:?}",
                obj
            ))),
        }
    }

    // Atom encoders
    fn encode_bool_atom(&mut self, v: bool) -> Result<()> {
        self.buffer.write_i8(-1)?; // type
        self.buffer.write_u8(0)?; // attr
        self.buffer.write_u8(v as u8)?;
        Ok(())
    }

    fn encode_byte_atom(&mut self, v: u8) -> Result<()> {
        self.buffer.write_i8(-4)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_u8(v)?;
        Ok(())
    }

    fn encode_short_atom(&mut self, v: i16) -> Result<()> {
        self.buffer.write_i8(-5)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i16::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_int_atom(&mut self, v: i32) -> Result<()> {
        self.buffer.write_i8(-6)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i32::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_long_atom(&mut self, v: i64) -> Result<()> {
        self.buffer.write_i8(-7)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i64::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_real_atom(&mut self, v: f32) -> Result<()> {
        self.buffer.write_i8(-8)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_f32::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_float_atom(&mut self, v: f64) -> Result<()> {
        self.buffer.write_i8(-9)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_f64::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_char_atom(&mut self, v: u8) -> Result<()> {
        self.buffer.write_i8(-10)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_u8(v)?;
        Ok(())
    }

    fn encode_symbol_atom(&mut self, v: &str) -> Result<()> {
        // Reject symbols containing NUL byte
        if v.as_bytes().contains(&0) {
            return Err(KdbError::EncodingError(
                "Symbol cannot contain NUL byte".into(),
            ));
        }

        self.buffer.write_i8(-11)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_all(v.as_bytes())?;
        self.buffer.write_u8(0)?; // null terminator
        Ok(())
    }

    fn encode_timestamp_atom(&mut self, v: i64) -> Result<()> {
        self.buffer.write_i8(-12)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i64::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_date_atom(&mut self, v: i32) -> Result<()> {
        self.buffer.write_i8(-14)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i32::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_datetime_atom(&mut self, v: f64) -> Result<()> {
        self.buffer.write_i8(-15)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_f64::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_timespan_atom(&mut self, v: i64) -> Result<()> {
        self.buffer.write_i8(-16)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i64::<LittleEndian>(v)?;
        Ok(())
    }

    fn encode_time_atom(&mut self, v: i32) -> Result<()> {
        self.buffer.write_i8(-19)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_i32::<LittleEndian>(v)?;
        Ok(())
    }

    // List encoders
    fn encode_bool_list(&mut self, v: &[bool]) -> Result<()> {
        self.buffer.write_i8(1)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_u8(item as u8)?;
        }
        Ok(())
    }

    fn encode_byte_list(&mut self, v: &[u8]) -> Result<()> {
        self.buffer.write_i8(4)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        self.buffer.write_all(v)?;
        Ok(())
    }

    fn encode_short_list(&mut self, v: &[i16]) -> Result<()> {
        self.buffer.write_i8(5)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i16::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_int_list(&mut self, v: &[i32]) -> Result<()> {
        self.buffer.write_i8(6)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i32::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_long_list(&mut self, v: &[i64]) -> Result<()> {
        self.buffer.write_i8(7)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i64::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_real_list(&mut self, v: &[f32]) -> Result<()> {
        self.buffer.write_i8(8)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_f32::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_float_list(&mut self, v: &[f64]) -> Result<()> {
        self.buffer.write_i8(9)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_f64::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_char_list(&mut self, v: &[u8]) -> Result<()> {
        self.buffer.write_i8(10)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        self.buffer.write_all(v)?;
        Ok(())
    }

    fn encode_symbol_list(&mut self, v: &[String]) -> Result<()> {
        self.buffer.write_i8(11)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for item in v {
            self.buffer.write_all(item.as_bytes())?;
            self.buffer.write_u8(0)?;
        }
        Ok(())
    }

    fn encode_timestamp_list(&mut self, v: &[i64]) -> Result<()> {
        self.buffer.write_i8(12)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i64::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_date_list(&mut self, v: &[i32]) -> Result<()> {
        self.buffer.write_i8(14)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i32::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_datetime_list(&mut self, v: &[f64]) -> Result<()> {
        self.buffer.write_i8(15)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_f64::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_timespan_list(&mut self, v: &[i64]) -> Result<()> {
        self.buffer.write_i8(16)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i64::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_time_list(&mut self, v: &[i32]) -> Result<()> {
        self.buffer.write_i8(19)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for &item in v {
            self.buffer.write_i32::<LittleEndian>(item)?;
        }
        Ok(())
    }

    fn encode_mixed_list(&mut self, v: &[KObject]) -> Result<()> {
        self.buffer.write_i8(0)?;
        self.buffer.write_u8(0)?;
        self.write_list_length(v.len())?;
        for item in v {
            self.encode_object(item)?;
        }
        Ok(())
    }

    fn encode_dict(&mut self, keys: &KObject, values: &KObject) -> Result<()> {
        self.buffer.write_i8(99)?;
        self.buffer.write_u8(0)?;
        self.encode_object(keys)?;
        self.encode_object(values)?;
        Ok(())
    }

    fn encode_table(&mut self, cols: &[String], data: &[KObject]) -> Result<()> {
        // Table is encoded as type 98 with a flipped dict
        self.buffer.write_i8(98)?;
        self.buffer.write_u8(0)?;

        // Dict type
        self.buffer.write_i8(99)?;
        self.buffer.write_u8(0)?;

        // Keys: symbol list of column names
        let keys = KObject::SymbolList(cols.to_vec());
        self.encode_object(&keys)?;

        // Values: mixed list of column data
        let values = KObject::MixedList(data.to_vec());
        self.encode_object(&values)?;

        Ok(())
    }

    fn encode_error(&mut self, msg: &str) -> Result<()> {
        self.buffer.write_i8(-128)?;
        self.buffer.write_u8(0)?;
        self.buffer.write_all(msg.as_bytes())?;
        self.buffer.write_u8(0)?;
        Ok(())
    }
}

impl Default for Encoder {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_int_atom() {
        let mut enc = Encoder::new();
        let obj = KObject::Int(42);
        let result = enc.encode_sync(&obj).unwrap();

        // Header: 8 bytes + type byte + attr byte + 4-byte int = 14 bytes total
        assert_eq!(result.len(), 14);
        assert_eq!(result[0], 1); // little-endian
        assert_eq!(result[1], 1); // sync
        assert_eq!(result[8], -6i8 as u8); // int type
    }

    #[test]
    fn test_encode_symbol_atom() {
        let mut enc = Encoder::new();
        let obj = KObject::Symbol("test".to_string());
        let result = enc.encode_sync(&obj).unwrap();

        assert_eq!(result[0], 1); // little-endian
        assert_eq!(result[8], -11i8 as u8); // symbol type
        assert!(result.ends_with(&[0])); // null terminator
    }

    #[test]
    fn test_encode_int_list() {
        let mut enc = Encoder::new();
        let obj = KObject::IntList(vec![1, 2, 3]);
        let result = enc.encode_sync(&obj).unwrap();

        assert_eq!(result[8], 6); // int list type
        // Length should be 3
        let len = i32::from_le_bytes([result[10], result[11], result[12], result[13]]);
        assert_eq!(len, 3);
    }
}
