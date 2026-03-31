//! kdb+ type system
//!
//! Defines the K object type hierarchy and conversions.
//! See: https://code.kx.com/q/basics/datatypes/

use chrono::{DateTime, NaiveDate, Utc};

/// kdb+ epoch: 2000-01-01 00:00:00 UTC
pub const KDB_EPOCH: i64 = 946684800;

/// kdb+ type codes
/// Negative for atoms, positive for lists, special codes for composites
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i8)]
pub enum KType {
    // Atoms (negative)
    Bool = -1,
    Byte = -4,
    Short = -5,
    Int = -6,
    Long = -7,
    Real = -8,
    Float = -9,
    Char = -10,
    Symbol = -11,
    Timestamp = -12,
    Month = -13,
    Date = -14,
    DateTime = -15,
    Timespan = -16,
    Minute = -17,
    Second = -18,
    Time = -19,

    // Lists (positive)
    BoolList = 1,
    ByteList = 4,
    ShortList = 5,
    IntList = 6,
    LongList = 7,
    RealList = 8,
    FloatList = 9,
    CharList = 10,
    SymbolList = 11,
    TimestampList = 12,
    MonthList = 13,
    DateList = 14,
    DateTimeList = 15,
    TimespanList = 16,
    MinuteList = 17,
    SecondList = 18,
    TimeList = 19,

    // Composites
    MixedList = 0,
    Dict = 99,
    Table = 98,
    Error = -128,
}

impl KType {
    /// Parse type code from i8
    pub fn from_i8(code: i8) -> Option<Self> {
        match code {
            -1 => Some(KType::Bool),
            -4 => Some(KType::Byte),
            -5 => Some(KType::Short),
            -6 => Some(KType::Int),
            -7 => Some(KType::Long),
            -8 => Some(KType::Real),
            -9 => Some(KType::Float),
            -10 => Some(KType::Char),
            -11 => Some(KType::Symbol),
            -12 => Some(KType::Timestamp),
            -13 => Some(KType::Month),
            -14 => Some(KType::Date),
            -15 => Some(KType::DateTime),
            -16 => Some(KType::Timespan),
            -17 => Some(KType::Minute),
            -18 => Some(KType::Second),
            -19 => Some(KType::Time),
            1 => Some(KType::BoolList),
            4 => Some(KType::ByteList),
            5 => Some(KType::ShortList),
            6 => Some(KType::IntList),
            7 => Some(KType::LongList),
            8 => Some(KType::RealList),
            9 => Some(KType::FloatList),
            10 => Some(KType::CharList),
            11 => Some(KType::SymbolList),
            12 => Some(KType::TimestampList),
            13 => Some(KType::MonthList),
            14 => Some(KType::DateList),
            15 => Some(KType::DateTimeList),
            16 => Some(KType::TimespanList),
            17 => Some(KType::MinuteList),
            18 => Some(KType::SecondList),
            19 => Some(KType::TimeList),
            0 => Some(KType::MixedList),
            99 => Some(KType::Dict),
            98 => Some(KType::Table),
            -128 => Some(KType::Error),
            _ => None,
        }
    }
}

/// K object representation
#[derive(Debug, Clone, PartialEq)]
pub enum KObject {
    // Atoms
    Bool(bool),
    Byte(u8),
    Short(i16),
    Int(i32),
    Long(i64),
    Real(f32),
    Float(f64),
    Char(u8),
    Symbol(String),
    Timestamp(i64),  // nanoseconds since 2000-01-01
    Month(i32),
    Date(i32),       // days since 2000-01-01
    DateTime(f64),   // days since 2000-01-01 (fractional)
    Timespan(i64),   // nanoseconds
    Minute(i32),
    Second(i32),
    Time(i32),       // milliseconds since midnight

    // Lists
    BoolList(Vec<bool>),
    ByteList(Vec<u8>),
    ShortList(Vec<i16>),
    IntList(Vec<i32>),
    LongList(Vec<i64>),
    RealList(Vec<f32>),
    FloatList(Vec<f64>),
    CharList(Vec<u8>),
    SymbolList(Vec<String>),
    TimestampList(Vec<i64>),
    MonthList(Vec<i32>),
    DateList(Vec<i32>),
    DateTimeList(Vec<f64>),
    TimespanList(Vec<i64>),
    MinuteList(Vec<i32>),
    SecondList(Vec<i32>),
    TimeList(Vec<i32>),

    // Composites
    MixedList(Vec<KObject>),
    Dict(Box<KObject>, Box<KObject>), // keys, values
    Table(Vec<String>, Vec<KObject>),  // column names, column data
    Error(String),
    Null,
}

impl KObject {
    /// Get the type code for this object
    pub fn type_code(&self) -> i8 {
        match self {
            KObject::Bool(_) => KType::Bool as i8,
            KObject::Byte(_) => KType::Byte as i8,
            KObject::Short(_) => KType::Short as i8,
            KObject::Int(_) => KType::Int as i8,
            KObject::Long(_) => KType::Long as i8,
            KObject::Real(_) => KType::Real as i8,
            KObject::Float(_) => KType::Float as i8,
            KObject::Char(_) => KType::Char as i8,
            KObject::Symbol(_) => KType::Symbol as i8,
            KObject::Timestamp(_) => KType::Timestamp as i8,
            KObject::Month(_) => KType::Month as i8,
            KObject::Date(_) => KType::Date as i8,
            KObject::DateTime(_) => KType::DateTime as i8,
            KObject::Timespan(_) => KType::Timespan as i8,
            KObject::Minute(_) => KType::Minute as i8,
            KObject::Second(_) => KType::Second as i8,
            KObject::Time(_) => KType::Time as i8,
            KObject::BoolList(_) => KType::BoolList as i8,
            KObject::ByteList(_) => KType::ByteList as i8,
            KObject::ShortList(_) => KType::ShortList as i8,
            KObject::IntList(_) => KType::IntList as i8,
            KObject::LongList(_) => KType::LongList as i8,
            KObject::RealList(_) => KType::RealList as i8,
            KObject::FloatList(_) => KType::FloatList as i8,
            KObject::CharList(_) => KType::CharList as i8,
            KObject::SymbolList(_) => KType::SymbolList as i8,
            KObject::TimestampList(_) => KType::TimestampList as i8,
            KObject::MonthList(_) => KType::MonthList as i8,
            KObject::DateList(_) => KType::DateList as i8,
            KObject::DateTimeList(_) => KType::DateTimeList as i8,
            KObject::TimespanList(_) => KType::TimespanList as i8,
            KObject::MinuteList(_) => KType::MinuteList as i8,
            KObject::SecondList(_) => KType::SecondList as i8,
            KObject::TimeList(_) => KType::TimeList as i8,
            KObject::MixedList(_) => KType::MixedList as i8,
            KObject::Dict(_, _) => KType::Dict as i8,
            KObject::Table(_, _) => KType::Table as i8,
            KObject::Error(_) => KType::Error as i8,
            KObject::Null => 101, // special null type
        }
    }

    /// Convert UTC DateTime to kdb+ timestamp (nanoseconds since 2000-01-01)
    pub fn from_datetime(dt: DateTime<Utc>) -> Self {
        let secs_since_epoch = dt.timestamp().saturating_sub(KDB_EPOCH);
        let nanos = secs_since_epoch
            .checked_mul(1_000_000_000)
            .and_then(|n| n.checked_add(dt.timestamp_subsec_nanos() as i64))
            .unwrap_or(i64::MAX);
        KObject::Timestamp(nanos)
    }

    /// Convert kdb+ timestamp to UTC DateTime
    pub fn to_datetime(&self) -> Option<DateTime<Utc>> {
        match self {
            KObject::Timestamp(nanos) => {
                let secs = KDB_EPOCH + nanos.div_euclid(1_000_000_000);
                let nsecs = nanos.rem_euclid(1_000_000_000) as u32;
                DateTime::from_timestamp(secs, nsecs)
            }
            _ => None,
        }
    }

    /// Convert kdb+ date (days since 2000-01-01) to NaiveDate
    pub fn to_date(&self) -> Option<NaiveDate> {
        match self {
            KObject::Date(days) => {
                let base = NaiveDate::from_ymd_opt(2000, 1, 1)?;
                base.checked_add_signed(chrono::Duration::days(*days as i64))
            }
            _ => None,
        }
    }

    /// Create kdb+ date from NaiveDate
    pub fn from_date(date: NaiveDate) -> Self {
        let base = NaiveDate::from_ymd_opt(2000, 1, 1).unwrap();
        let days = date.signed_duration_since(base).num_days() as i32;
        KObject::Date(days)
    }
}

// Null value constants
impl KObject {
    pub const NULL_BOOL: bool = false;
    pub const NULL_BYTE: u8 = 0;
    pub const NULL_SHORT: i16 = i16::MIN;
    pub const NULL_INT: i32 = i32::MIN;
    pub const NULL_LONG: i64 = i64::MIN;
    pub const NULL_REAL: f32 = f32::NAN;
    pub const NULL_FLOAT: f64 = f64::NAN;
    pub const NULL_CHAR: u8 = b' ';
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_type_codes() {
        assert_eq!(KObject::Int(42).type_code(), -6);
        assert_eq!(KObject::IntList(vec![1, 2, 3]).type_code(), 6);
        assert_eq!(KObject::Symbol("test".to_string()).type_code(), -11);
    }

    #[test]
    fn test_datetime_conversion() {
        let dt = DateTime::parse_from_rfc3339("2020-01-01T00:00:00Z")
            .unwrap()
            .with_timezone(&Utc);
        let kobj = KObject::from_datetime(dt);
        let converted = kobj.to_datetime().unwrap();
        assert_eq!(dt, converted);
    }

    #[test]
    fn test_date_conversion() {
        let date = NaiveDate::from_ymd_opt(2020, 6, 15).unwrap();
        let kobj = KObject::from_date(date);
        let converted = kobj.to_date().unwrap();
        assert_eq!(date, converted);
    }

    #[test]
    fn test_type_from_i8() {
        assert_eq!(KType::from_i8(-6), Some(KType::Int));
        assert_eq!(KType::from_i8(6), Some(KType::IntList));
        assert_eq!(KType::from_i8(99), Some(KType::Dict));
        assert_eq!(KType::from_i8(98), Some(KType::Table));
        assert_eq!(KType::from_i8(127), None);
    }
}
