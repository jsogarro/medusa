/ Tests for .conf namespace (config/config.q, parser.q, validator.q, loader.q)

\l tests/q/test_framework.q
\l src/q/config/config.q

/ ========================================
/ Parser tests
/ ========================================

test_parser_trim:{
  .test.assertEqual["Trim leading spaces"; "hello"; .conf.parser.trim["  hello"]];
  .test.assertEqual["Trim trailing spaces"; "world"; .conf.parser.trim["world  "]];
  .test.assertEqual["Trim both"; "test"; .conf.parser.trim["  test  "]];
 }

test_parser_parseLine_comment:{
  .test.assertEqual["Comment line skipped"; (); .conf.parser.parseLine["# this is a comment"]];
 }

test_parser_parseLine_empty:{
  .test.assertEqual["Empty line skipped"; (); .conf.parser.parseLine[""]];
  .test.assertEqual["Whitespace line skipped"; (); .conf.parser.parseLine["   "]];
 }

test_parser_parseLine_section:{
  result:.conf.parser.parseLine["[strategy]"];
  .test.assertEqual["Section detected"; `section; result 0];
  .test.assertEqual["Section name parsed"; `strategy; result 1];
 }

test_parser_parseLine_kv:{
  result:.conf.parser.parseLine["tick_sleep=100"];
  .test.assertEqual["KV detected"; `kv; result 0];
  .test.assertEqual["Key parsed"; `tick_sleep; result 1];
  .test.assertEqual["Value parsed"; "100"; result 2];
 }

/ ========================================
/ Validator tests
/ ========================================

test_validator_coerceInt:{
  .test.assertEqual["Parse valid int"; 42; .conf.validator.coerceInt["42"]];
  .test.assertEqual["Parse negative"; -10; .conf.validator.coerceInt["-10"]];
 }

test_validator_coerceFloat:{
  .test.assertEqual["Parse valid float"; 3.14; .conf.validator.coerceFloat["3.14"]];
  .test.assertEqual["Parse negative float"; -2.5; .conf.validator.coerceFloat["-2.5"]];
 }

test_validator_coerceSymbol:{
  .test.assertEqual["Convert to symbol"; `hello; .conf.validator.coerceSymbol["hello"]];
 }

test_validator_coerceBool_true:{
  .test.assert["'true' is 1b"; .conf.validator.coerceBool["true"]];
  .test.assert["'1' is 1b"; .conf.validator.coerceBool["1"]];
  .test.assert["'yes' is 1b"; .conf.validator.coerceBool["yes"]];
 }

test_validator_coerceBool_false:{
  .test.assert["'false' is 0b"; not .conf.validator.coerceBool["false"]];
  .test.assert["'0' is 0b"; not .conf.validator.coerceBool["0"]];
  .test.assert["'no' is 0b"; not .conf.validator.coerceBool["no"]];
 }

test_validator_coerce_typed:{
  .test.assertEqual["Coerce as int"; 42; .conf.validator.coerce[`int; "42"]];
  .test.assertEqual["Coerce as float"; 3.14; .conf.validator.coerce[`float; "3.14"]];
  .test.assertEqual["Coerce as symbol"; `test; .conf.validator.coerce[`symbol; "test"]];
  .test.assert["Coerce as bool"; .conf.validator.coerce[`bool; "true"]];
  .test.assertEqual["Coerce as string"; "raw"; .conf.validator.coerce[`string; "raw"]];
 }

/ ========================================
/ Loader tests
/ ========================================

test_loader_merge_empty:{
  base:()!();
  override:()!();
  result:.conf.loader.merge[base; override];
  .test.assertEqual["Merge empty dicts"; ()!(); result];
 }

test_loader_merge_override:{
  base:enlist[`section1]!enlist `key1`key2!(10;20);
  override:enlist[`section1]!enlist `key2`key3!(99;30);
  result:.conf.loader.merge[base; override];
  .test.assertEqual["key2 overridden"; 99; result[`section1;`key2]];
  .test.assertEqual["key3 added"; 30; result[`section1;`key3]];
  .test.assertEqual["key1 preserved"; 10; result[`section1;`key1]];
 }

/ ========================================
/ Config API tests
/ ========================================

test_config_get_default:{
  .conf.current:enlist[`test]!enlist `foo!(42);
  val:.conf.get[`test; `bar; 99];
  .test.assertEqual["Missing key returns default"; 99; val];
 }

test_config_get_existing:{
  .conf.current:enlist[`test]!enlist `foo!(42);
  val:.conf.get[`test; `foo; 99];
  .test.assertEqual["Existing key returns value"; 42; val];
 }

test_config_set:{
  .conf.current:()!();
  .conf.set[`section1; `key1; 123];
  .test.assertEqual["Set value persists"; 123; .conf.current[`section1;`key1]];
 }

test_config_getTyped:{
  .conf.current:enlist[`test]!enlist (enlist `num)!enlist "42";
  val:.conf.getTyped[`test; `num; `int; 0];
  .test.assertEqual["Type coercion applied"; 42; val];
  .test.assertType["Coerced to int"; -7h; val];
 }

-1 "Config tests loaded";
