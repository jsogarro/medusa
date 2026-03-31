//! kdb+ IPC wire format decoder
//!
//! Decodes binary IPC messages into K objects.

use crate::error::{KdbError, Result};
use crate::types::{KObject, KType};
use byteorder::{LittleEndian, ReadBytesExt};
use std::io::{Cursor, Read};

/// Maximum list length to prevent memory exhaustion
const MAX_LIST_LENGTH: usize = 10_000_000;

/// Maximum symbol length to prevent memory exhaustion
const MAX_SYMBOL_LENGTH: usize = 1024;

/// Maximum recursion depth for nested structures
const MAX_RECURSION_DEPTH: usize = 100;

/// Decoder for kdb+ IPC messages
pub struct Decoder {
    cursor: Cursor<Vec<u8>>,
    depth: usize,
}

impl Decoder {
    /// Create a new decoder from raw bytes
    pub fn new(data: Vec<u8>) -> Self {
        Self {
            cursor: Cursor::new(data),
            depth: 0,
        }
    }

    /// Decode a complete message (header + payload)
    pub fn decode_message(&mut self) -> Result<KObject> {
        // Read header (8 bytes)
        let byte_order = self.cursor.read_u8()?;
        if byte_order != 1 {
            return Err(KdbError::InvalidMessage(
                "Big-endian not supported".to_string(),
            ));
        }

        let _msg_type = self.cursor.read_u8()?;
        let _compression = self.cursor.read_u8()?;
        let _reserved = self.cursor.read_u8()?;
        let _total_length = self.cursor.read_u32::<LittleEndian>()?;

        // Decode payload
        self.decode_object()
    }

    /// Decode a K object
    pub fn decode_object(&mut self) -> Result<KObject> {
        // Check recursion depth
        if self.depth > MAX_RECURSION_DEPTH {
            return Err(KdbError::DecodingError(format!(
                "Maximum recursion depth exceeded: {}",
                MAX_RECURSION_DEPTH
            )));
        }

        self.depth += 1;
        let type_code = self.cursor.read_i8()?;
        let _attr = self.cursor.read_u8()?;

        let result = match KType::from_i8(type_code) {
            Some(KType::Bool) => self.decode_bool_atom(),
            Some(KType::Byte) => self.decode_byte_atom(),
            Some(KType::Short) => self.decode_short_atom(),
            Some(KType::Int) => self.decode_int_atom(),
            Some(KType::Long) => self.decode_long_atom(),
            Some(KType::Real) => self.decode_real_atom(),
            Some(KType::Float) => self.decode_float_atom(),
            Some(KType::Char) => self.decode_char_atom(),
            Some(KType::Symbol) => self.decode_symbol_atom(),
            Some(KType::Timestamp) => self.decode_timestamp_atom(),
            Some(KType::Date) => self.decode_date_atom(),
            Some(KType::DateTime) => self.decode_datetime_atom(),
            Some(KType::Timespan) => self.decode_timespan_atom(),
            Some(KType::Time) => self.decode_time_atom(),

            Some(KType::BoolList) => self.decode_bool_list(),
            Some(KType::ByteList) => self.decode_byte_list(),
            Some(KType::ShortList) => self.decode_short_list(),
            Some(KType::IntList) => self.decode_int_list(),
            Some(KType::LongList) => self.decode_long_list(),
            Some(KType::RealList) => self.decode_real_list(),
            Some(KType::FloatList) => self.decode_float_list(),
            Some(KType::CharList) => self.decode_char_list(),
            Some(KType::SymbolList) => self.decode_symbol_list(),
            Some(KType::TimestampList) => self.decode_timestamp_list(),
            Some(KType::DateList) => self.decode_date_list(),
            Some(KType::DateTimeList) => self.decode_datetime_list(),
            Some(KType::TimespanList) => self.decode_timespan_list(),
            Some(KType::TimeList) => self.decode_time_list(),

            Some(KType::MixedList) => self.decode_mixed_list(),
            Some(KType::Dict) => self.decode_dict(),
            Some(KType::Table) => self.decode_table(),
            Some(KType::Error) => self.decode_error(),

            _ => Err(KdbError::InvalidTypeCode(type_code)),
        };

        self.depth -= 1;
        result
    }

    // Helper methods for safe reading

    /// Read list length with validation
    fn read_list_length(&mut self) -> Result<usize> {
        let len_i32 = self.cursor.read_i32::<LittleEndian>()?;

        if len_i32 < 0 {
            return Err(KdbError::DecodingError(format!(
                "Invalid list length: {} (negative)",
                len_i32
            )));
        }

        let len = len_i32 as usize;
        if len > MAX_LIST_LENGTH {
            return Err(KdbError::DecodingError(format!(
                "List length {} exceeds maximum {}",
                len, MAX_LIST_LENGTH
            )));
        }

        Ok(len)
    }

    // Atom decoders
    fn decode_bool_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_u8()?;
        Ok(KObject::Bool(v != 0))
    }

    fn decode_byte_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_u8()?;
        Ok(KObject::Byte(v))
    }

    fn decode_short_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i16::<LittleEndian>()?;
        Ok(KObject::Short(v))
    }

    fn decode_int_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i32::<LittleEndian>()?;
        Ok(KObject::Int(v))
    }

    fn decode_long_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i64::<LittleEndian>()?;
        Ok(KObject::Long(v))
    }

    fn decode_real_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_f32::<LittleEndian>()?;
        Ok(KObject::Real(v))
    }

    fn decode_float_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_f64::<LittleEndian>()?;
        Ok(KObject::Float(v))
    }

    fn decode_char_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_u8()?;
        Ok(KObject::Char(v))
    }

    fn decode_symbol_atom(&mut self) -> Result<KObject> {
        let s = self.read_symbol()?;
        Ok(KObject::Symbol(s))
    }

    fn decode_timestamp_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i64::<LittleEndian>()?;
        Ok(KObject::Timestamp(v))
    }

    fn decode_date_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i32::<LittleEndian>()?;
        Ok(KObject::Date(v))
    }

    fn decode_datetime_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_f64::<LittleEndian>()?;
        Ok(KObject::DateTime(v))
    }

    fn decode_timespan_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i64::<LittleEndian>()?;
        Ok(KObject::Timespan(v))
    }

    fn decode_time_atom(&mut self) -> Result<KObject> {
        let v = self.cursor.read_i32::<LittleEndian>()?;
        Ok(KObject::Time(v))
    }

    // List decoders
    fn decode_bool_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_u8()? != 0);
        }
        Ok(KObject::BoolList(v))
    }

    fn decode_byte_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = vec![0u8; len];
        self.cursor.read_exact(&mut v)?;
        Ok(KObject::ByteList(v))
    }

    fn decode_short_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i16::<LittleEndian>()?);
        }
        Ok(KObject::ShortList(v))
    }

    fn decode_int_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i32::<LittleEndian>()?);
        }
        Ok(KObject::IntList(v))
    }

    fn decode_long_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i64::<LittleEndian>()?);
        }
        Ok(KObject::LongList(v))
    }

    fn decode_real_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_f32::<LittleEndian>()?);
        }
        Ok(KObject::RealList(v))
    }

    fn decode_float_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_f64::<LittleEndian>()?);
        }
        Ok(KObject::FloatList(v))
    }

    fn decode_char_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = vec![0u8; len];
        self.cursor.read_exact(&mut v)?;
        Ok(KObject::CharList(v))
    }

    fn decode_symbol_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.read_symbol()?);
        }
        Ok(KObject::SymbolList(v))
    }

    fn decode_timestamp_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i64::<LittleEndian>()?);
        }
        Ok(KObject::TimestampList(v))
    }

    fn decode_date_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i32::<LittleEndian>()?);
        }
        Ok(KObject::DateList(v))
    }

    fn decode_datetime_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_f64::<LittleEndian>()?);
        }
        Ok(KObject::DateTimeList(v))
    }

    fn decode_timespan_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i64::<LittleEndian>()?);
        }
        Ok(KObject::TimespanList(v))
    }

    fn decode_time_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.cursor.read_i32::<LittleEndian>()?);
        }
        Ok(KObject::TimeList(v))
    }

    fn decode_mixed_list(&mut self) -> Result<KObject> {
        let len = self.read_list_length()?;
        let mut v = Vec::with_capacity(len);
        for _ in 0..len {
            v.push(self.decode_object()?);
        }
        Ok(KObject::MixedList(v))
    }

    fn decode_dict(&mut self) -> Result<KObject> {
        let keys = Box::new(self.decode_object()?);
        let values = Box::new(self.decode_object()?);
        Ok(KObject::Dict(keys, values))
    }

    fn decode_table(&mut self) -> Result<KObject> {
        // Table is a flipped dict
        // Read dict type and attr
        let dict_type = self.cursor.read_i8()?;
        if dict_type != 99 {
            return Err(KdbError::DecodingError(format!(
                "Expected dict type 99 in table, got {}",
                dict_type
            )));
        }
        let _dict_attr = self.cursor.read_u8()?;

        // Decode keys (symbol list of column names)
        let keys = self.decode_object()?;
        let cols = match keys {
            KObject::SymbolList(names) => names,
            _ => {
                return Err(KdbError::DecodingError(
                    "Table keys must be symbol list".to_string(),
                ))
            }
        };

        // Decode values (mixed list of column data)
        let values = self.decode_object()?;
        let data = match values {
            KObject::MixedList(cols) => cols,
            _ => {
                return Err(KdbError::DecodingError(
                    "Table values must be mixed list".to_string(),
                ))
            }
        };

        Ok(KObject::Table(cols, data))
    }

    fn decode_error(&mut self) -> Result<KObject> {
        let msg = self.read_symbol()?;
        Ok(KObject::Error(msg))
    }

    // Helper: read null-terminated string with length validation
    fn read_symbol(&mut self) -> Result<String> {
        let mut bytes = Vec::new();
        loop {
            let byte = self.cursor.read_u8()?;
            if byte == 0 {
                break;
            }
            bytes.push(byte);

            if bytes.len() > MAX_SYMBOL_LENGTH {
                return Err(KdbError::DecodingError(format!(
                    "Symbol length {} exceeds maximum {}",
                    bytes.len(),
                    MAX_SYMBOL_LENGTH
                )));
            }
        }
        String::from_utf8(bytes).map_err(|e| {
            KdbError::DecodingError(format!("Invalid UTF-8 in symbol: {}", e))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::encode::Encoder;

    #[test]
    fn test_roundtrip_int_atom() {
        let mut enc = Encoder::new();
        let obj = KObject::Int(42);
        let encoded = enc.encode_sync(&obj).unwrap();

        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();

        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_roundtrip_symbol_atom() {
        let mut enc = Encoder::new();
        let obj = KObject::Symbol("test".to_string());
        let encoded = enc.encode_sync(&obj).unwrap();

        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();

        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_roundtrip_int_list() {
        let mut enc = Encoder::new();
        let obj = KObject::IntList(vec![1, 2, 3, 4, 5]);
        let encoded = enc.encode_sync(&obj).unwrap();

        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();

        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_roundtrip_symbol_list() {
        let mut enc = Encoder::new();
        let obj = KObject::SymbolList(vec![
            "apple".to_string(),
            "banana".to_string(),
            "cherry".to_string(),
        ]);
        let encoded = enc.encode_sync(&obj).unwrap();

        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();

        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_roundtrip_mixed_list() {
        let mut enc = Encoder::new();
        let obj = KObject::MixedList(vec![
            KObject::Int(42),
            KObject::Symbol("test".to_string()),
            KObject::Float(123.456),
        ]);
        let encoded = enc.encode_sync(&obj).unwrap();

        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();

        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_decode_negative_list_length() {
        // Craft a message with negative list length
        let msg = vec![
            1, 1, 0, 0, 18, 0, 0, 0, // header (little-endian, sync, 18 bytes)
            6, 0, // type: IntList, attr: 0
            0xFF, 0xFF, 0xFF, 0xFF, // -1 as i32
        ];

        let mut dec = Decoder::new(msg);
        let result = dec.decode_message();

        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), KdbError::DecodingError(_)));
    }

    #[test]
    fn test_decode_oversized_list() {
        // Craft a message with length > MAX_LIST_LENGTH (10,000,000)
        let oversized_len = 20_000_000i32;
        let mut msg = vec![
            1, 1, 0, 0, 18, 0, 0, 0, // header
            6, 0, // type: IntList, attr: 0
        ];
        msg.extend_from_slice(&oversized_len.to_le_bytes());

        let mut dec = Decoder::new(msg);
        let result = dec.decode_message();

        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), KdbError::DecodingError(_)));
    }

    #[test]
    fn test_decode_truncated_message() {
        // Encode a valid int list, then truncate it
        let mut enc = Encoder::new();
        let obj = KObject::IntList(vec![1, 2, 3, 4, 5]);
        let mut encoded = enc.encode_sync(&obj).unwrap();

        // Truncate the message
        encoded.truncate(encoded.len() - 5);

        let mut dec = Decoder::new(encoded);
        let result = dec.decode_message();

        assert!(result.is_err());
    }

    #[test]
    fn test_roundtrip_empty_lists() {
        // Empty IntList
        let mut enc = Encoder::new();
        let obj = KObject::IntList(vec![]);
        let encoded = enc.encode_sync(&obj).unwrap();
        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();
        assert_eq!(obj, decoded);

        // Empty SymbolList
        let obj = KObject::SymbolList(vec![]);
        let encoded = enc.encode_sync(&obj).unwrap();
        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();
        assert_eq!(obj, decoded);
    }

    #[test]
    fn test_roundtrip_max_values() {
        // i64::MAX
        let mut enc = Encoder::new();
        let obj = KObject::Long(i64::MAX);
        let encoded = enc.encode_sync(&obj).unwrap();
        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();
        assert_eq!(obj, decoded);

        // i64::MIN
        let obj = KObject::Long(i64::MIN);
        let encoded = enc.encode_sync(&obj).unwrap();
        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();
        assert_eq!(obj, decoded);

        // f64::INFINITY
        let obj = KObject::Float(f64::INFINITY);
        let encoded = enc.encode_sync(&obj).unwrap();
        let mut dec = Decoder::new(encoded);
        let decoded = dec.decode_message().unwrap();
        assert_eq!(obj, decoded);
    }
}
