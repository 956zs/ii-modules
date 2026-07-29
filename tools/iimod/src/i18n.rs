//! Development-time translation source extraction and catalog checking.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::Result;
use serde::de::{MapAccess, Visitor};
use serde::{Deserialize, Deserializer, Serialize};
use walkdir::WalkDir;

use crate::exit::{self, bail};
use crate::manifest;
use crate::ops;

#[derive(Debug, Serialize)]
struct ExtractOne {
    module: String,
    sources: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ExtractAll {
    modules: BTreeMap<String, Vec<String>>,
}

#[derive(Debug)]
struct Unit {
    name: String,
    text: String,
}

#[derive(Debug)]
struct ModuleCatalog {
    id: String,
    sources: BTreeSet<String>,
}

#[derive(Debug, Clone)]
struct CallSite {
    source: String,
    line: usize,
    column: usize,
    expression: String,
    literal: Option<String>,
    arg_count: usize,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct DynamicCatalogFile {
    schema_version: u32,
    declarations: Vec<DynamicDeclaration>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct DynamicDeclaration {
    source: String,
    expression: String,
    sources: Vec<String>,
}

#[derive(Debug, PartialEq, Eq)]
struct PlaceholderProfile {
    counts: BTreeMap<u8, usize>,
    max_index: usize,
}

#[derive(Debug)]
struct DictionaryReport {
    entries: BTreeMap<String, String>,
    warnings: Vec<String>,
}

#[derive(Debug)]
struct StrictDictionary(Vec<(String, serde_json::Value)>);

impl<'de> Deserialize<'de> for StrictDictionary {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct DictionaryVisitor;

        impl<'de> Visitor<'de> for DictionaryVisitor {
            type Value = StrictDictionary;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("a JSON object with unique string-to-string entries")
            }

            fn visit_map<M>(self, mut map: M) -> std::result::Result<Self::Value, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut entries = Vec::new();
                let mut keys = BTreeSet::new();
                while let Some((key, value)) = map.next_entry::<String, serde_json::Value>()? {
                    if !keys.insert(key.clone()) {
                        return Err(serde::de::Error::custom(format!(
                            "duplicate dictionary key {key:?}"
                        )));
                    }
                    entries.push((key, value));
                }
                Ok(StrictDictionary(entries))
            }
        }

        deserializer.deserialize_map(DictionaryVisitor)
    }
}

pub(crate) fn validate_payload_i18n(payload: &Path) -> Result<Vec<String>> {
    let catalog = extract_payload(payload)?;
    let mut warnings = Vec::new();
    check_payload_dictionaries(
        payload,
        &catalog,
        &["zh_TW".to_string()],
        false,
        &mut warnings,
    )?;
    Ok(warnings)
}

pub(crate) fn cmd_extract(source: Option<&Path>, all: bool, max_size: u64) -> Result<()> {
    if all {
        let modules = load_repository_catalogs(&std::env::current_dir()?)?;
        let output = modules
            .into_iter()
            .map(|module| (module.id, module.sources.into_iter().collect()))
            .collect();
        println!(
            "{}",
            serde_json::to_string_pretty(&ExtractAll { modules: output })?
        );
        return Ok(());
    }

    let source = source.ok_or_else(|| bail(exit::USAGE, "SOURCE or --all is required"))?;
    let payload = ops::load_payload(source, max_size)?;
    let catalog = extract_payload(&payload.dir)?;
    println!(
        "{}",
        serde_json::to_string_pretty(&ExtractOne {
            module: catalog.id,
            sources: catalog.sources.into_iter().collect(),
        })?
    );
    Ok(())
}

pub(crate) fn cmd_check(
    source: Option<&Path>,
    all: bool,
    locales: &[String],
    deny_orphans: bool,
    max_size: u64,
) -> Result<()> {
    let required_locales = required_locales(all, locales)?;
    if all {
        let catalogs = load_repository_catalogs(&std::env::current_dir()?)?;
        let mut dictionaries = BTreeMap::new();
        let mut warnings = Vec::new();
        for catalog in &catalogs {
            let payload = repository_payload_for(&std::env::current_dir()?, &catalog.id)?;
            dictionaries.insert(
                catalog.id.clone(),
                check_payload_dictionaries(
                    &payload,
                    catalog,
                    &required_locales,
                    deny_orphans,
                    &mut warnings,
                )?,
            );
        }
        check_repository_conflicts(&catalogs, &dictionaries, &required_locales)?;
        print_warnings(&warnings);
        println!("i18n check ok: {} modules", catalogs.len());
        return Ok(());
    }

    let source = source.ok_or_else(|| bail(exit::USAGE, "SOURCE or --all is required"))?;
    let payload = ops::load_payload(source, max_size)?;
    let catalog = extract_payload(&payload.dir)?;
    let mut warnings = Vec::new();
    check_payload_dictionaries(
        &payload.dir,
        &catalog,
        &required_locales,
        deny_orphans,
        &mut warnings,
    )?;
    print_warnings(&warnings);
    println!("i18n check ok: {}", catalog.id);
    Ok(())
}

fn required_locales(all: bool, requested: &[String]) -> Result<Vec<String>> {
    let mut locales = if requested.is_empty() {
        if all {
            vec!["zh_TW".to_string(), "zh_CN".to_string()]
        } else {
            vec!["zh_TW".to_string()]
        }
    } else {
        requested.to_vec()
    };
    for locale in &locales {
        if !manifest::is_valid_locale(locale) {
            return Err(bail(exit::VALIDATION, format!("invalid locale {locale:?}")));
        }
    }
    locales.sort();
    locales.dedup();
    Ok(locales)
}

fn print_warnings(warnings: &[String]) {
    for warning in warnings {
        eprintln!("warning: {warning}");
    }
}

fn extract_payload(payload: &Path) -> Result<ModuleCatalog> {
    let bytes = std::fs::read(payload.join("module.json")).map_err(|_| {
        bail(
            exit::VALIDATION,
            format!("{}: module.json missing", payload.display()),
        )
    })?;
    let manifest = manifest::parse(&bytes)?;
    manifest::validate(&manifest)?;
    let dir_name = payload
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or_default();
    if dir_name != manifest.id {
        return Err(bail(
            exit::VALIDATION,
            format!("payload dir {dir_name:?} != manifest id {:?}", manifest.id),
        ));
    }

    let mut units = source_units(payload)?;
    for (index, patch) in manifest.patches.iter().enumerate() {
        units.push(Unit {
            name: format!("module.json#patches/{index}/content"),
            text: patch.content.clone(),
        });
    }
    units.sort_by(|left, right| left.name.cmp(&right.name));

    let declarations = load_dynamic_catalog(payload)?;
    let mut declaration_index = BTreeMap::new();
    for (index, declaration) in declarations.iter().enumerate() {
        let key = (
            declaration.source.clone(),
            normalize_expression(&declaration.expression),
        );
        if declaration_index.insert(key, index).is_some() {
            return Err(bail(
                exit::VALIDATION,
                format!(
                    "i18n.sources.json: duplicate declaration for {} expression {:?}",
                    declaration.source, declaration.expression
                ),
            ));
        }
    }

    let mut matched = BTreeSet::new();
    let mut sources = BTreeSet::new();
    for unit in units {
        for call in scan_calls(&unit.name, &unit.text)? {
            if let Some(literal) = &call.literal {
                validate_call_source(&call, literal)?;
                sources.insert(literal.clone());
                continue;
            }
            let key = (call.source.clone(), normalize_expression(&call.expression));
            let Some(index) = declaration_index.get(&key).copied() else {
                return Err(call_error(
                    &call,
                    format!(
                        "dynamic Translation.tr argument {:?} has no exact i18n.sources.json declaration",
                        call.expression
                    ),
                ));
            };
            matched.insert(index);
            for declared_source in &declarations[index].sources {
                validate_call_source(&call, declared_source)?;
                sources.insert(declared_source.clone());
            }
        }
    }
    for (index, declaration) in declarations.iter().enumerate() {
        if !matched.contains(&index) {
            return Err(bail(
                exit::VALIDATION,
                format!(
                    "i18n.sources.json: unmatched declaration for {} expression {:?}",
                    declaration.source, declaration.expression
                ),
            ));
        }
    }

    Ok(ModuleCatalog {
        id: manifest.id,
        sources,
    })
}

fn source_units(payload: &Path) -> Result<Vec<Unit>> {
    let mut files: Vec<PathBuf> = WalkDir::new(payload)
        .follow_links(false)
        .into_iter()
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            entry
                .path()
                .extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| matches!(extension, "qml" | "js"))
        })
        .map(|entry| entry.into_path())
        .collect();
    files.sort_by(|left, right| {
        left.strip_prefix(payload)
            .unwrap_or(left)
            .cmp(right.strip_prefix(payload).unwrap_or(right))
    });

    files
        .into_iter()
        .map(|path| {
            let name = path
                .strip_prefix(payload)
                .unwrap_or(&path)
                .to_string_lossy()
                .into_owned();
            let text = std::fs::read_to_string(&path).map_err(|error| {
                bail(
                    exit::VALIDATION,
                    format!("{name}: cannot read UTF-8 source: {error}"),
                )
            })?;
            Ok(Unit { name, text })
        })
        .collect()
}

fn load_dynamic_catalog(payload: &Path) -> Result<Vec<DynamicDeclaration>> {
    let path = payload.join("i18n.sources.json");
    if !path.exists() {
        return Ok(Vec::new());
    }
    parse_dynamic_catalog(&std::fs::read(path)?)
}

fn parse_dynamic_catalog(bytes: &[u8]) -> Result<Vec<DynamicDeclaration>> {
    let parsed: DynamicCatalogFile = serde_json::from_slice(bytes)
        .map_err(|error| bail(exit::VALIDATION, format!("i18n.sources.json: {error}")))?;
    if parsed.schema_version != 1 {
        return Err(bail(
            exit::VALIDATION,
            format!(
                "i18n.sources.json: unsupported schemaVersion {}",
                parsed.schema_version
            ),
        ));
    }
    let mut declarations = parsed.declarations;
    for declaration in &mut declarations {
        if !is_valid_declaration_source(&declaration.source) {
            return Err(bail(
                exit::VALIDATION,
                format!(
                    "i18n.sources.json: invalid declaration source {:?}",
                    declaration.source
                ),
            ));
        }
        declaration.expression = normalize_expression(&declaration.expression);
        if declaration.expression.is_empty() {
            return Err(bail(
                exit::VALIDATION,
                "i18n.sources.json: declaration expression must be non-empty",
            ));
        }
        if declaration.sources.is_empty() {
            return Err(bail(
                exit::VALIDATION,
                "i18n.sources.json: declaration sources must be non-empty",
            ));
        }
        let original_len = declaration.sources.len();
        declaration.sources.sort();
        declaration.sources.dedup();
        if declaration.sources.len() != original_len {
            return Err(bail(
                exit::VALIDATION,
                "i18n.sources.json: duplicate declared source key",
            ));
        }
        for source in &declaration.sources {
            placeholder_profile(source).map_err(|error| {
                bail(
                    exit::VALIDATION,
                    format!("i18n.sources.json: invalid source {source:?}: {error}"),
                )
            })?;
        }
    }
    declarations.sort_by(|left, right| {
        (&left.source, &left.expression).cmp(&(&right.source, &right.expression))
    });
    for pair in declarations.windows(2) {
        if pair[0].source == pair[1].source && pair[0].expression == pair[1].expression {
            return Err(bail(
                exit::VALIDATION,
                format!(
                    "i18n.sources.json: duplicate declaration for {} expression {:?}",
                    pair[0].source, pair[0].expression
                ),
            ));
        }
    }
    Ok(declarations)
}

fn is_valid_declaration_source(source: &str) -> bool {
    let is_file =
        manifest::is_safe_rel_path(source) && (source.ends_with(".qml") || source.ends_with(".js"));
    let patch_index = source
        .strip_prefix("module.json#patches/")
        .and_then(|rest| rest.strip_suffix("/content"));
    let is_patch = patch_index.is_some_and(|index| {
        !index.is_empty()
            && index.bytes().all(|byte| byte.is_ascii_digit())
            && (index == "0" || !index.starts_with('0'))
    });
    is_file || is_patch
}

fn normalize_expression(expression: &str) -> String {
    let bytes = expression.as_bytes();
    let mut output = String::new();
    let mut index = 0;
    let mut pending_space = false;
    while index < bytes.len() {
        if bytes[index].is_ascii_whitespace() {
            pending_space = !output.is_empty();
            index += 1;
            continue;
        }
        if pending_space {
            output.push(' ');
            pending_space = false;
        }
        if matches!(bytes[index], b'\'' | b'"' | b'`') {
            let quote = bytes[index];
            output.push(quote as char);
            index += 1;
            while index < bytes.len() {
                let ch = expression[index..]
                    .chars()
                    .next()
                    .expect("valid UTF-8 boundary");
                output.push(ch);
                index += ch.len_utf8();
                if ch == '\\' {
                    if let Some(escaped) = expression[index..].chars().next() {
                        output.push(escaped);
                        index += escaped.len_utf8();
                    }
                } else if ch as u32 == quote as u32 {
                    break;
                }
            }
            continue;
        }
        let ch = expression[index..]
            .chars()
            .next()
            .expect("valid UTF-8 boundary");
        output.push(ch);
        index += ch.len_utf8();
    }
    output
}

fn scan_calls(source: &str, text: &str) -> Result<Vec<CallSite>> {
    let mut calls = Vec::new();
    scan_calls_range(source, text, 0, text.len(), &mut calls)?;
    Ok(calls)
}

fn scan_calls_range(
    source: &str,
    text: &str,
    start: usize,
    end: usize,
    calls: &mut Vec<CallSite>,
) -> Result<()> {
    let bytes = text.as_bytes();
    let mut index = start;
    while index < end {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = scan_template_interpolations(source, text, index, calls)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        if !starts(bytes, index, b"Translation")
            || !service_call_boundary(bytes, index, index + b"Translation".len())
        {
            index += char_len(text, index);
            continue;
        }

        let call_start = index;
        let mut cursor = skip_trivia(source, text, index + b"Translation".len())?;
        if bytes.get(cursor) != Some(&b'.') {
            index += b"Translation".len();
            continue;
        }
        cursor = skip_trivia(source, text, cursor + 1)?;
        if !starts(bytes, cursor, b"tr")
            || !identifier_boundary(bytes, cursor, cursor + b"tr".len())
        {
            index += b"Translation".len();
            continue;
        }
        cursor = skip_trivia(source, text, cursor + b"tr".len())?;
        if bytes.get(cursor) != Some(&b'(') {
            index += b"Translation".len();
            continue;
        }

        let argument_start = cursor + 1;
        let argument_end = find_call_close(source, text, cursor)?;
        let argument = text[argument_start..argument_end].trim();
        if argument.is_empty() {
            return Err(diag(
                source,
                text,
                call_start,
                "Translation.tr requires exactly one argument",
            ));
        }
        if has_top_level_comma(source, text, argument_start, argument_end)? {
            return Err(diag(
                source,
                text,
                call_start,
                "Translation.tr requires exactly one argument",
            ));
        }

        let trimmed_start = argument_start
            + text[argument_start..argument_end]
                .find(|ch: char| !ch.is_whitespace())
                .unwrap_or(0);
        let literal = if matches!(text.as_bytes()[trimmed_start], b'\'' | b'"') {
            let (literal_end, value) = parse_string(source, text, trimmed_start)?;
            if !text[literal_end..argument_end].trim().is_empty() {
                return Err(diag(
                    source,
                    text,
                    call_start,
                    "Translation.tr argument must be exactly one string literal; concatenation is unsupported",
                ));
            }
            Some(value)
        } else if text.as_bytes()[trimmed_start] == b'`' {
            match parse_template_literal(source, text, trimmed_start)? {
                (literal_end, Some(value))
                    if text[literal_end..argument_end].trim().is_empty() =>
                {
                    Some(value)
                }
                (literal_end, None) if text[literal_end..argument_end].trim().is_empty() => None,
                _ => {
                    return Err(diag(
                        source,
                        text,
                        call_start,
                        "Translation.tr argument must be exactly one string literal; concatenation is unsupported",
                    ))
                }
            }
        } else {
            None
        };

        let (mut arg_count, after) = count_arg_chain(source, text, argument_end + 1)?;
        arg_count += enclosing_group_arg_count(source, text, call_start, after)?;
        let (line, column) = location(text, call_start);
        calls.push(CallSite {
            source: source.to_string(),
            line,
            column,
            expression: normalize_expression(argument),
            literal,
            arg_count,
        });
        scan_calls_range(source, text, argument_start, after, calls)?;
        index = after;
    }
    Ok(())
}

fn count_arg_chain(source: &str, text: &str, mut after: usize) -> Result<(usize, usize)> {
    let bytes = text.as_bytes();
    let mut arg_count = 0;
    loop {
        let chain_start = skip_trivia(source, text, after)?;
        if bytes.get(chain_start) != Some(&b'.') {
            break;
        }
        let mut member = skip_trivia(source, text, chain_start + 1)?;
        if !starts(bytes, member, b"arg")
            || !identifier_boundary(bytes, member, member + b"arg".len())
        {
            break;
        }
        member = skip_trivia(source, text, member + b"arg".len())?;
        if bytes.get(member) != Some(&b'(') {
            break;
        }
        after = find_call_close(source, text, member)? + 1;
        arg_count += 1;
    }
    Ok((arg_count, after))
}

fn enclosing_group_arg_count(
    source: &str,
    text: &str,
    call_start: usize,
    call_end: usize,
) -> Result<usize> {
    let mut groups = grouping_parentheses(source, text)?;
    groups.sort_by_key(|(open, _)| std::cmp::Reverse(*open));
    let mut count = 0;
    let mut contained_end = call_end;
    for (open, close) in groups {
        if open < call_start
            && close >= contained_end
            && group_is_translated_ternary(source, text, open, close)?
        {
            let (postfix_count, postfix_end) = count_arg_chain(source, text, close + 1)?;
            count += postfix_count;
            contained_end = postfix_end.max(close + 1);
        }
    }
    Ok(count)
}

fn group_is_translated_ternary(
    source: &str,
    text: &str,
    open: usize,
    close: usize,
) -> Result<bool> {
    let Some((question, colon)) = top_level_ternary(source, text, open + 1, close)? else {
        return Ok(false);
    };
    Ok(
        is_complete_translation_expression(source, text, question + 1, colon)?
            && is_complete_translation_expression(source, text, colon + 1, close)?,
    )
}

fn top_level_ternary(
    source: &str,
    text: &str,
    start: usize,
    end: usize,
) -> Result<Option<(usize, usize)>> {
    let bytes = text.as_bytes();
    let mut stack = Vec::new();
    let mut question = None;
    let mut index = start;
    while index < end {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        match bytes[index] {
            b'(' => stack.push(b')'),
            b'[' => stack.push(b']'),
            b'{' => stack.push(b'}'),
            b')' | b']' | b'}' => {
                stack.pop();
            }
            b'?' if stack.is_empty() => {
                if question.is_some() {
                    return Ok(None);
                }
                question = Some(index);
            }
            b':' if stack.is_empty() && question.is_some() => {
                return Ok(Some((question.expect("checked"), index)));
            }
            _ => {}
        }
        index += char_len(text, index);
    }
    Ok(None)
}

fn is_complete_translation_expression(
    source: &str,
    text: &str,
    start: usize,
    end: usize,
) -> Result<bool> {
    let bytes = text.as_bytes();
    let call_start = skip_trivia(source, text, start)?;
    if call_start >= end
        || !starts(bytes, call_start, b"Translation")
        || !service_call_boundary(bytes, call_start, call_start + b"Translation".len())
    {
        return Ok(false);
    }
    let mut cursor = skip_trivia(source, text, call_start + b"Translation".len())?;
    if bytes.get(cursor) != Some(&b'.') {
        return Ok(false);
    }
    cursor = skip_trivia(source, text, cursor + 1)?;
    if !starts(bytes, cursor, b"tr") || !identifier_boundary(bytes, cursor, cursor + b"tr".len()) {
        return Ok(false);
    }
    cursor = skip_trivia(source, text, cursor + b"tr".len())?;
    if bytes.get(cursor) != Some(&b'(') {
        return Ok(false);
    }
    let close = find_call_close(source, text, cursor)?;
    let (_, after) = count_arg_chain(source, text, close + 1)?;
    Ok(skip_trivia(source, text, after)? == end)
}

fn grouping_parentheses(source: &str, text: &str) -> Result<Vec<(usize, usize)>> {
    let bytes = text.as_bytes();
    let mut stack = Vec::new();
    let mut groups = Vec::new();
    let mut index = 0;
    let mut can_end_expression = false;
    while index < bytes.len() {
        if bytes[index].is_ascii_whitespace() {
            index += 1;
            continue;
        }
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            can_end_expression = true;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            can_end_expression = true;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            can_end_expression = true;
            continue;
        }
        if is_identifier_byte(bytes[index]) {
            while bytes
                .get(index)
                .is_some_and(|byte| is_identifier_byte(*byte))
            {
                index += 1;
            }
            can_end_expression = true;
            continue;
        }
        if bytes[index].is_ascii_digit() {
            while bytes
                .get(index)
                .is_some_and(|byte| byte.is_ascii_alphanumeric() || *byte == b'.')
            {
                index += 1;
            }
            can_end_expression = true;
            continue;
        }
        match bytes[index] {
            b'(' => {
                stack.push((b')', index, !can_end_expression));
                can_end_expression = false;
            }
            b'[' => {
                stack.push((b']', index, false));
                can_end_expression = false;
            }
            b'{' => {
                stack.push((b'}', index, false));
                can_end_expression = false;
            }
            b')' | b']' | b'}' => {
                if let Some((expected, open, grouping)) = stack.pop() {
                    if expected == bytes[index] && grouping {
                        groups.push((open, index));
                    }
                }
                can_end_expression = true;
            }
            b'.' => {}
            _ => can_end_expression = false,
        }
        index += char_len(text, index);
    }
    Ok(groups)
}

fn find_call_close(source: &str, text: &str, open: usize) -> Result<usize> {
    let bytes = text.as_bytes();
    let mut stack = vec![b')'];
    let mut index = open + 1;
    while index < bytes.len() {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        match bytes[index] {
            b'(' => stack.push(b')'),
            b'[' => stack.push(b']'),
            b'{' => stack.push(b'}'),
            b')' | b']' | b'}' => {
                if stack.pop() != Some(bytes[index]) {
                    return Err(diag(source, text, index, "unbalanced translation call"));
                }
                if stack.is_empty() {
                    return Ok(index);
                }
            }
            _ => {}
        }
        index += char_len(text, index);
    }
    Err(diag(
        source,
        text,
        open,
        "unterminated Translation.tr or .arg call",
    ))
}

fn has_top_level_comma(source: &str, text: &str, start: usize, end: usize) -> Result<bool> {
    let bytes = text.as_bytes();
    let mut stack = Vec::new();
    let mut index = start;
    while index < end {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        match bytes[index] {
            b'(' => stack.push(b')'),
            b'[' => stack.push(b']'),
            b'{' => stack.push(b'}'),
            b')' | b']' | b'}' => {
                stack.pop();
            }
            b',' if stack.is_empty() => return Ok(true),
            _ => {}
        }
        index += char_len(text, index);
    }
    Ok(false)
}

fn scan_template_interpolations(
    source: &str,
    text: &str,
    start: usize,
    calls: &mut Vec<CallSite>,
) -> Result<usize> {
    let bytes = text.as_bytes();
    let mut index = start + 1;
    while index < bytes.len() {
        if bytes[index] == b'`' {
            return Ok(index + 1);
        }
        if starts(bytes, index, b"${") {
            let close = find_matching_brace(source, text, index + 1)?;
            scan_calls_range(source, text, index + 2, close, calls)?;
            index = close + 1;
            continue;
        }
        if bytes[index] == b'\\' {
            index = parse_string_escape(source, text, index)?.0;
            continue;
        }
        index += char_len(text, index);
    }
    Err(diag(source, text, start, "unterminated template string"))
}

fn skip_template(source: &str, text: &str, start: usize) -> Result<usize> {
    Ok(parse_template_literal(source, text, start)?.0)
}

fn parse_template_literal(
    source: &str,
    text: &str,
    start: usize,
) -> Result<(usize, Option<String>)> {
    let bytes = text.as_bytes();
    let mut index = start + 1;
    let mut value = String::new();
    let mut interpolated = false;
    while index < bytes.len() {
        if bytes[index] == b'`' {
            return Ok((index + 1, (!interpolated).then_some(value)));
        }
        if starts(bytes, index, b"${") {
            interpolated = true;
            let close = find_matching_brace(source, text, index + 1)?;
            index = close + 1;
            continue;
        }
        if bytes[index] == b'\\' {
            let (end, decoded) = parse_string_escape(source, text, index)?;
            if let Some(decoded) = decoded {
                value.push(decoded);
            }
            index = end;
            continue;
        }
        let ch = text[index..].chars().next().expect("valid UTF-8 boundary");
        value.push(ch);
        index += ch.len_utf8();
    }
    Err(diag(source, text, start, "unterminated template string"))
}

fn find_matching_brace(source: &str, text: &str, open: usize) -> Result<usize> {
    let bytes = text.as_bytes();
    let mut depth = 1_usize;
    let mut index = open + 1;
    while index < bytes.len() {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        match bytes[index] {
            b'{' => depth += 1,
            b'}' => {
                depth -= 1;
                if depth == 0 {
                    return Ok(index);
                }
            }
            _ => {}
        }
        index += char_len(text, index);
    }
    Err(diag(
        source,
        text,
        open,
        "unterminated template interpolation",
    ))
}

fn parse_string_escape(
    source: &str,
    text: &str,
    escape_at: usize,
) -> Result<(usize, Option<char>)> {
    let bytes = text.as_bytes();
    let index = escape_at + 1;
    let Some(escaped) = bytes.get(index).copied() else {
        return Err(diag(source, text, escape_at, "unterminated string escape"));
    };
    let pair = match escaped {
        b'n' => (index + 1, Some('\n')),
        b'r' => (index + 1, Some('\r')),
        b't' => (index + 1, Some('\t')),
        b'b' => (index + 1, Some('\u{0008}')),
        b'f' => (index + 1, Some('\u{000c}')),
        b'v' => (index + 1, Some('\u{000b}')),
        b'0' => (index + 1, Some('\0')),
        b'\\' => (index + 1, Some('\\')),
        b'\'' => (index + 1, Some('\'')),
        b'"' => (index + 1, Some('"')),
        b'`' => (index + 1, Some('`')),
        b'x' => {
            let (ch, end) = decode_escape(source, text, escape_at, index + 1, 2)?;
            (end, Some(ch))
        }
        b'u' => {
            let (ch, end) = decode_unicode_escape(source, text, escape_at, index + 1)?;
            (end, Some(ch))
        }
        b'\n' => (index + 1, None),
        other => (index + 1, Some(other as char)),
    };
    Ok(pair)
}

fn parse_string(source: &str, text: &str, start: usize) -> Result<(usize, String)> {
    let bytes = text.as_bytes();
    let quote = bytes[start];
    let mut index = start + 1;
    let mut value = String::new();
    while index < bytes.len() {
        if bytes[index] == quote {
            return Ok((index + 1, value));
        }
        if quote == b'`' && starts(bytes, index, b"${") {
            return Err(diag(
                source,
                text,
                index,
                "interpolated strings are not valid translation sources",
            ));
        }
        if bytes[index] == b'\\' {
            let escape_at = index;
            index += 1;
            let Some(escaped) = bytes.get(index).copied() else {
                return Err(diag(source, text, escape_at, "unterminated string escape"));
            };
            match escaped {
                b'n' => value.push('\n'),
                b'r' => value.push('\r'),
                b't' => value.push('\t'),
                b'b' => value.push('\u{0008}'),
                b'f' => value.push('\u{000c}'),
                b'v' => value.push('\u{000b}'),
                b'0' => value.push('\0'),
                b'\\' => value.push('\\'),
                b'\'' => value.push('\''),
                b'"' => value.push('"'),
                b'`' => value.push('`'),
                b'x' => {
                    let (ch, end) = decode_escape(source, text, escape_at, index + 1, 2)?;
                    value.push(ch);
                    index = end;
                    continue;
                }
                b'u' => {
                    let (ch, end) = decode_unicode_escape(source, text, escape_at, index + 1)?;
                    value.push(ch);
                    index = end;
                    continue;
                }
                b'\n' => {}
                other => value.push(other as char),
            }
            index += 1;
        } else {
            let ch = text[index..].chars().next().expect("valid UTF-8 boundary");
            value.push(ch);
            index += ch.len_utf8();
        }
    }
    Err(diag(source, text, start, "unterminated string literal"))
}

fn decode_unicode_escape(
    source: &str,
    text: &str,
    escape_at: usize,
    digits_start: usize,
) -> Result<(char, usize)> {
    let (first, mut end) = decode_escape_code(source, text, escape_at, digits_start, 4)?;
    let code = if (0xd800..=0xdbff).contains(&first) {
        if text.as_bytes().get(end..end + 2) != Some(b"\\u") {
            return Err(diag(
                source,
                text,
                escape_at,
                "high surrogate must be followed by a low surrogate escape",
            ));
        }
        let (second, second_end) = decode_escape_code(source, text, end, end + 2, 4)?;
        if !(0xdc00..=0xdfff).contains(&second) {
            return Err(diag(source, text, end, "invalid low surrogate escape"));
        }
        end = second_end;
        0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00)
    } else if (0xdc00..=0xdfff).contains(&first) {
        return Err(diag(
            source,
            text,
            escape_at,
            "unexpected low surrogate escape",
        ));
    } else {
        first
    };
    let ch = char::from_u32(code)
        .ok_or_else(|| diag(source, text, escape_at, "invalid Unicode scalar"))?;
    Ok((ch, end))
}

fn decode_escape_code(
    source: &str,
    text: &str,
    escape_at: usize,
    digits_start: usize,
    digits_len: usize,
) -> Result<(u32, usize)> {
    let end = digits_start + digits_len;
    let digits = text
        .get(digits_start..end)
        .ok_or_else(|| diag(source, text, escape_at, "incomplete numeric escape"))?;
    let code = u32::from_str_radix(digits, 16)
        .map_err(|_| diag(source, text, escape_at, "invalid numeric escape"))?;
    Ok((code, end))
}

fn decode_escape(
    source: &str,
    text: &str,
    escape_at: usize,
    digits_start: usize,
    digits_len: usize,
) -> Result<(char, usize)> {
    let (code, end) = decode_escape_code(source, text, escape_at, digits_start, digits_len)?;
    let ch = char::from_u32(code)
        .ok_or_else(|| diag(source, text, escape_at, "invalid Unicode scalar"))?;
    Ok((ch, end))
}

fn validate_call_source(call: &CallSite, source: &str) -> Result<()> {
    let profile = placeholder_profile(source).map_err(|error| {
        call_error(
            call,
            format!("invalid translation source {source:?}: {error}"),
        )
    })?;
    if call.arg_count != profile.max_index {
        return Err(call_error(
            call,
            format!(
                "source {source:?} requires {} immediate .arg() calls, found {}",
                profile.max_index, call.arg_count
            ),
        ));
    }
    Ok(())
}

fn placeholder_profile(source: &str) -> Result<PlaceholderProfile> {
    if source.is_empty() || source.trim() != source {
        return Err(bail(
            exit::VALIDATION,
            "source must be non-empty without leading or trailing whitespace",
        ));
    }
    if source.chars().any(char::is_control) {
        return Err(bail(
            exit::VALIDATION,
            "source must not contain control characters",
        ));
    }
    let bytes = source.as_bytes();
    let mut counts = BTreeMap::new();
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] != b'%' {
            index += char_len(source, index);
            continue;
        }
        if bytes.get(index + 1) == Some(&b'n') {
            return Err(bail(
                exit::VALIDATION,
                "%n plural placeholders are unsupported",
            ));
        }
        if bytes.get(index + 1).is_some_and(u8::is_ascii_digit) {
            let mut end = index + 1;
            while bytes.get(end).is_some_and(u8::is_ascii_digit) {
                end += 1;
            }
            let number = source[index + 1..end].parse::<usize>().unwrap_or(100);
            if !(1..=99).contains(&number) || end - (index + 1) > 2 || bytes[index + 1] == b'0' {
                return Err(bail(
                    exit::VALIDATION,
                    format!("non-canonical placeholder {}", &source[index..end]),
                ));
            }
            *counts.entry(number as u8).or_insert(0) += 1;
            index = end;
            continue;
        }
        if bytes
            .get(index + 1)
            .is_some_and(|byte| byte.is_ascii_alphanumeric() || *byte == b'_')
        {
            return Err(bail(
                exit::VALIDATION,
                format!("unsupported placeholder near {:?}", &source[index..]),
            ));
        }
        index += 1;
    }
    let max_index = counts.keys().next_back().copied().unwrap_or(0) as usize;
    for expected in 1..=max_index {
        if !counts.contains_key(&(expected as u8)) {
            return Err(bail(
                exit::VALIDATION,
                format!("placeholder indices must be contiguous; missing %{expected}"),
            ));
        }
    }
    Ok(PlaceholderProfile { counts, max_index })
}

fn check_payload_dictionaries(
    payload: &Path,
    catalog: &ModuleCatalog,
    locales: &[String],
    deny_orphans: bool,
    warnings: &mut Vec<String>,
) -> Result<BTreeMap<String, BTreeMap<String, String>>> {
    let mut dictionaries = BTreeMap::new();
    for locale in locales {
        let relative = format!("translations/{locale}.json");
        let path = payload.join(&relative);
        let bytes = std::fs::read(&path).map_err(|_| {
            bail(
                exit::VALIDATION,
                format!("{}: missing required locale {locale}", catalog.id),
            )
        })?;
        let report = validate_dictionary(locale, &bytes, &catalog.sources, deny_orphans).map_err(
            |error| {
                bail(
                    exit::VALIDATION,
                    format!("{}:{relative}: {error}", catalog.id),
                )
            },
        )?;
        warnings.extend(
            report
                .warnings
                .into_iter()
                .map(|warning| format!("{}:{relative}: {warning}", catalog.id)),
        );
        dictionaries.insert(locale.clone(), report.entries);
    }
    Ok(dictionaries)
}

fn validate_dictionary(
    locale: &str,
    bytes: &[u8],
    sources: &BTreeSet<String>,
    deny_orphans: bool,
) -> Result<DictionaryReport> {
    let text = std::str::from_utf8(bytes).map_err(|error| {
        bail(
            exit::VALIDATION,
            format!("dictionary is not UTF-8: {error}"),
        )
    })?;
    let StrictDictionary(raw_entries) = serde_json::from_slice(bytes).map_err(|error| {
        bail(
            exit::VALIDATION,
            format!("malformed dictionary JSON: {error}"),
        )
    })?;
    let raw_keys: Vec<&str> = raw_entries.iter().map(|(key, _)| key.as_str()).collect();
    let mut sorted_keys = raw_keys.clone();
    sorted_keys.sort();
    if raw_keys != sorted_keys {
        return Err(bail(
            exit::VALIDATION,
            "dictionary keys must use Unicode-codepoint order",
        ));
    }

    let mut entries = BTreeMap::new();
    let mut warnings = Vec::new();
    for (key, value) in raw_entries {
        let translated = value.as_str().ok_or_else(|| {
            bail(
                exit::VALIDATION,
                format!("dictionary must contain only string-to-string entries; key {key:?}"),
            )
        })?;
        placeholder_profile(&key).map_err(|error| {
            bail(
                exit::VALIDATION,
                format!("invalid dictionary key {key:?}: {error}"),
            )
        })?;
        if translated.trim().is_empty() {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}:{key:?}: translated value must be non-empty"),
            ));
        }
        if translated.chars().any(char::is_control) {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}:{key:?}: translated value contains control characters"),
            ));
        }
        let marker = translated
            .trim()
            .strip_suffix(':')
            .unwrap_or(translated.trim());
        if ["TODO", "TBD", "FIXME", "TRANSLATE", "UNTRANSLATED"]
            .iter()
            .any(|candidate| marker.eq_ignore_ascii_case(candidate))
        {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}:{key:?}: explicit placeholder marker {translated:?}"),
            ));
        }
        let source_profile = placeholder_profile(&key)?;
        let translated_profile = translation_placeholder_profile(translated)?;
        if source_profile.counts != translated_profile.counts {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}:{key:?}: placeholder multiset differs from source"),
            ));
        }
        if translated == key {
            warnings.push(format!("{key:?}: translation is identical to source"));
        }
        entries.insert(key, translated.to_string());
    }

    let canonical = serde_json::to_string_pretty(&entries)? + "\n";
    if text != canonical {
        return Err(bail(
            exit::VALIDATION,
            "dictionary format must be two-space JSON with one final newline",
        ));
    }

    for source in sources {
        if !entries.contains_key(source) {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}: missing key {source:?}"),
            ));
        }
    }
    for orphan in entries.keys().filter(|key| !sources.contains(*key)) {
        if deny_orphans {
            return Err(bail(
                exit::VALIDATION,
                format!("{locale}: orphan key {orphan:?}"),
            ));
        }
        warnings.push(format!("{orphan:?}: orphan key"));
    }
    warnings.sort();
    Ok(DictionaryReport { entries, warnings })
}

fn translation_placeholder_profile(value: &str) -> Result<PlaceholderProfile> {
    if value.chars().any(char::is_control) {
        return Err(bail(
            exit::VALIDATION,
            "translation contains control characters",
        ));
    }
    let padded = value.trim();
    if padded.is_empty() {
        return Err(bail(exit::VALIDATION, "translation is empty"));
    }
    placeholder_profile(padded)
}

fn check_repository_conflicts(
    catalogs: &[ModuleCatalog],
    dictionaries: &BTreeMap<String, BTreeMap<String, BTreeMap<String, String>>>,
    locales: &[String],
) -> Result<()> {
    let mut contributions: BTreeMap<(String, String), BTreeMap<String, Vec<String>>> =
        BTreeMap::new();
    for catalog in catalogs {
        for locale in locales {
            let dict = &dictionaries[&catalog.id][locale];
            for (source, value) in dict {
                contributions
                    .entry((locale.clone(), source.clone()))
                    .or_default()
                    .entry(value.clone())
                    .or_default()
                    .push(catalog.id.clone());
            }
        }
    }
    let conflicts: Vec<String> = contributions
        .into_iter()
        .filter(|(_, values)| values.len() > 1)
        .map(|((locale, source), values)| {
            let details = values
                .into_iter()
                .flat_map(|(value, modules)| {
                    modules
                        .into_iter()
                        .map(move |module| format!("{module}={value:?}"))
                })
                .collect::<Vec<_>>()
                .join(", ");
            format!("{locale}:{source:?}: {details}")
        })
        .collect();
    if conflicts.is_empty() {
        Ok(())
    } else {
        Err(bail(
            exit::VALIDATION,
            format!(
                "repository translation conflicts:\n  {}",
                conflicts.join("\n  ")
            ),
        ))
    }
}

fn load_repository_catalogs(start: &Path) -> Result<Vec<ModuleCatalog>> {
    let root = repository_root(start)?;
    let mut catalogs = Vec::new();
    for payload in repository_module_paths(&root)? {
        let directory_id = payload
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or_default()
            .to_string();
        let catalog = extract_payload(&payload)?;
        if directory_id != catalog.id {
            return Err(bail(
                exit::VALIDATION,
                format!(
                    "modules/{directory_id}: directory id does not match manifest id {:?}",
                    catalog.id
                ),
            ));
        }
        catalogs.push(catalog);
    }
    catalogs.sort_by(|left, right| left.id.cmp(&right.id));
    for pair in catalogs.windows(2) {
        if pair[0].id == pair[1].id {
            return Err(bail(
                exit::VALIDATION,
                format!("duplicate repository module id {:?}", pair[0].id),
            ));
        }
    }
    Ok(catalogs)
}

fn repository_payload_for(start: &Path, id: &str) -> Result<PathBuf> {
    Ok(repository_root(start)?.join("modules").join(id))
}

fn repository_module_paths(root: &Path) -> Result<Vec<PathBuf>> {
    let mut payloads: Vec<PathBuf> = std::fs::read_dir(root.join("modules"))?
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| path.is_dir() && path.join("module.json").is_file())
        .collect();
    payloads.sort();
    Ok(payloads)
}

fn repository_root(start: &Path) -> Result<PathBuf> {
    let mut cursor = start.to_path_buf();
    loop {
        if cursor.join("tools/iimod/Cargo.toml").is_file() && cursor.join("modules").is_dir() {
            return Ok(cursor);
        }
        if !cursor.pop() {
            return Err(bail(
                exit::VALIDATION,
                format!("cannot discover repository root from {}", start.display()),
            ));
        }
    }
}

fn skip_regex_literal(source: &str, text: &str, start: usize) -> Result<usize> {
    let bytes = text.as_bytes();
    let mut index = start + 1;
    let mut in_class = false;
    while index < bytes.len() {
        match bytes[index] {
            b'\\' => {
                index += 1;
                if index >= bytes.len() || bytes[index] == b'\n' {
                    return Err(diag(source, text, start, "unterminated regex literal"));
                }
                index += char_len(text, index);
            }
            b'[' if !in_class => {
                in_class = true;
                index += 1;
            }
            b']' if in_class => {
                in_class = false;
                index += 1;
            }
            b'/' if !in_class => {
                index += 1;
                while bytes
                    .get(index)
                    .is_some_and(|byte| is_identifier_byte(*byte))
                {
                    index += 1;
                }
                return Ok(index);
            }
            b'\n' | b'\r' => {
                return Err(diag(source, text, start, "unterminated regex literal"));
            }
            _ => index += char_len(text, index),
        }
    }
    Err(diag(source, text, start, "unterminated regex literal"))
}

fn is_regex_start(source: &str, text: &str, slash: usize) -> Result<bool> {
    let bytes = text.as_bytes();
    let Some(previous_index) = bytes[..slash]
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
    else {
        return Ok(true);
    };
    let previous = bytes[previous_index];
    if matches!(
        previous,
        b'(' | b'['
            | b'{'
            | b'='
            | b','
            | b':'
            | b';'
            | b'!'
            | b'?'
            | b'&'
            | b'|'
            | b'+'
            | b'-'
            | b'*'
            | b'%'
            | b'^'
            | b'~'
            | b'<'
            | b'>'
    ) {
        return Ok(true);
    }
    if previous == b')' && closes_control_header(source, text, previous_index)? {
        return Ok(true);
    }
    if previous == b'}' && closes_statement_block(source, text, previous_index)? {
        return Ok(true);
    }
    if !is_identifier_byte(previous) {
        return Ok(false);
    }

    let mut word_start = previous_index;
    while word_start > 0 && is_identifier_byte(bytes[word_start - 1]) {
        word_start -= 1;
    }
    let keyword = &text[word_start..=previous_index];
    Ok(matches!(keyword, "return" | "throw" | "case" | "else")
        && bytes[..word_start]
            .iter()
            .rfind(|byte| !byte.is_ascii_whitespace())
            .is_none_or(|byte| *byte != b'.'))
}

fn closes_control_header(source: &str, text: &str, close: usize) -> Result<bool> {
    let Some(open) = matching_open_delimiter(source, text, close, b'(', b')')? else {
        return Ok(false);
    };
    let bytes = text.as_bytes();
    let Some(previous_index) = bytes[..open]
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
    else {
        return Ok(false);
    };
    if !is_identifier_byte(bytes[previous_index]) {
        return Ok(false);
    }
    let mut word_start = previous_index;
    while word_start > 0 && is_identifier_byte(bytes[word_start - 1]) {
        word_start -= 1;
    }
    Ok(matches!(
        &text[word_start..=previous_index],
        "if" | "while" | "for" | "with" | "switch" | "catch"
    ))
}

fn closes_statement_block(source: &str, text: &str, close: usize) -> Result<bool> {
    let Some(open) = matching_open_delimiter(source, text, close, b'{', b'}')? else {
        return Ok(false);
    };
    let bytes = text.as_bytes();
    let Some(previous_index) = bytes[..open]
        .iter()
        .rposition(|byte| !byte.is_ascii_whitespace())
    else {
        return Ok(true);
    };
    if bytes[previous_index] == b')' {
        return closes_control_header(source, text, previous_index);
    }
    if !is_identifier_byte(bytes[previous_index]) {
        return Ok(false);
    }
    let mut word_start = previous_index;
    while word_start > 0 && is_identifier_byte(bytes[word_start - 1]) {
        word_start -= 1;
    }
    Ok(matches!(
        &text[word_start..=previous_index],
        "else" | "try" | "finally" | "do"
    ))
}

fn matching_open_delimiter(
    source: &str,
    text: &str,
    close: usize,
    open_byte: u8,
    close_byte: u8,
) -> Result<Option<usize>> {
    let bytes = text.as_bytes();
    let mut stack = Vec::new();
    let mut index = 0;
    while index <= close && index < bytes.len() {
        if starts(bytes, index, b"//") {
            index = skip_line_comment(bytes, index + 2);
            continue;
        }
        if starts(bytes, index, b"/*") {
            index = skip_block_comment(source, text, index)?;
            continue;
        }
        if matches!(bytes[index], b'\'' | b'"') {
            index = parse_string(source, text, index)?.0;
            continue;
        }
        if bytes[index] == b'`' {
            index = skip_template(source, text, index)?;
            continue;
        }
        if bytes[index] == b'/' && is_regex_start(source, text, index)? {
            index = skip_regex_literal(source, text, index)?;
            continue;
        }
        if bytes[index] == open_byte {
            stack.push(index);
        } else if bytes[index] == close_byte {
            let Some(open) = stack.pop() else {
                return Ok(None);
            };
            if index == close {
                return Ok(Some(open));
            }
        }
        index += char_len(text, index);
    }
    Ok(None)
}

fn skip_line_comment(bytes: &[u8], mut index: usize) -> usize {
    while index < bytes.len() && bytes[index] != b'\n' {
        index += 1;
    }
    index
}

fn skip_block_comment(source: &str, text: &str, mut index: usize) -> Result<usize> {
    let start = index;
    index += 2;
    while index + 1 < text.len() {
        if starts(text.as_bytes(), index, b"*/") {
            return Ok(index + 2);
        }
        index += char_len(text, index);
    }
    Err(diag(source, text, start, "unterminated block comment"))
}

fn skip_trivia(source: &str, text: &str, mut index: usize) -> Result<usize> {
    loop {
        index = skip_space(text.as_bytes(), index);
        if starts(text.as_bytes(), index, b"//") {
            index = skip_line_comment(text.as_bytes(), index + 2);
        } else if starts(text.as_bytes(), index, b"/*") {
            index = skip_block_comment(source, text, index)?;
        } else {
            return Ok(index);
        }
    }
}

fn skip_space(bytes: &[u8], mut index: usize) -> usize {
    while bytes.get(index).is_some_and(u8::is_ascii_whitespace) {
        index += 1;
    }
    index
}

fn starts(bytes: &[u8], index: usize, expected: &[u8]) -> bool {
    bytes.get(index..index.saturating_add(expected.len())) == Some(expected)
}

fn service_call_boundary(bytes: &[u8], start: usize, end: usize) -> bool {
    identifier_boundary(bytes, start, end)
        && bytes[..start]
            .iter()
            .rfind(|byte| !byte.is_ascii_whitespace())
            .is_none_or(|byte| *byte != b'.')
}

fn is_identifier_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'$')
}

fn identifier_boundary(bytes: &[u8], start: usize, end: usize) -> bool {
    (start == 0 || !is_identifier_byte(bytes[start - 1]))
        && bytes.get(end).is_none_or(|byte| !is_identifier_byte(*byte))
}

fn char_len(text: &str, index: usize) -> usize {
    text[index..]
        .chars()
        .next()
        .map(char::len_utf8)
        .unwrap_or(1)
}

fn location(text: &str, offset: usize) -> (usize, usize) {
    let prefix = &text[..offset.min(text.len())];
    let line = prefix.bytes().filter(|byte| *byte == b'\n').count() + 1;
    let column = prefix
        .rsplit_once('\n')
        .map_or(prefix.chars().count() + 1, |(_, tail)| {
            tail.chars().count() + 1
        });
    (line, column)
}

fn call_error(call: &CallSite, message: impl std::fmt::Display) -> anyhow::Error {
    bail(
        exit::VALIDATION,
        format!("{}:{}:{}: {message}", call.source, call.line, call.column),
    )
}

fn diag(source: &str, text: &str, offset: usize, message: &str) -> anyhow::Error {
    let (line, column) = location(text, offset);
    bail(
        exit::VALIDATION,
        format!("{source}:{line}:{column}: {message}"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn error_text<T: std::fmt::Debug>(result: Result<T>) -> String {
        result.unwrap_err().to_string()
    }

    #[test]
    fn scanner_handles_literals_comments_multiline_and_arg_chains() {
        let text = r#"
// Translation.tr("ignored")
property string fake: "Translation.tr('ignored too')"
property string first: Translation
    . tr (
        "Open \"quoted\" %1"
    ).arg(value)
property string second: Translation.tr(`Static backtick`)
/* Translation.tr("also ignored") */
"#;
        let calls = scan_calls("settings.qml", text).unwrap();
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].literal.as_deref(), Some("Open \"quoted\" %1"));
        assert_eq!(calls[0].arg_count, 1);
        assert_eq!(calls[1].literal.as_deref(), Some("Static backtick"));
        assert_eq!(calls[1].arg_count, 0);
        assert!(scan_calls("empty.qml", "Item {} // nothing")
            .unwrap()
            .is_empty());
        assert_eq!(
            scan_calls(
                "escapes.qml",
                r#"Translation.tr("Unicode ☺")/* gap */.arg(/* gap */ value)"#,
            )
            .unwrap()[0]
                .literal
                .as_deref(),
            Some("Unicode ☺")
        );
        assert_eq!(
            scan_calls("logic.js", "const x = Translation.tr('From JS');").unwrap()[0]
                .literal
                .as_deref(),
            Some("From JS")
        );
        assert!(scan_calls("false.qml", "OtherTranslation.tr('No')")
            .unwrap()
            .is_empty());
        assert!(scan_calls("member.qml", "obj.Translation.tr('No')")
            .unwrap()
            .is_empty());
        assert_eq!(
            scan_calls("unicode.qml", r#"Translation.tr("Face 😀")"#).unwrap()[0]
                .literal
                .as_deref(),
            Some("Face 😀")
        );
        let surrogate_pair = format!("{}uD83D{}uDE00", '\\', '\\');
        assert_eq!(
            decode_unicode_escape("unicode.qml", &surrogate_pair, 0, 2).unwrap(),
            ('😀', 12)
        );
    }

    #[test]
    fn scanner_attributes_parenthesized_ternary_postfix_args_to_each_branch() {
        let text = r#"
property string text: (
    full
        ? Translation.tr("Full in %1")
        : Translation.tr("Empty in %1")
) /* harmless */ . arg(value)
"#;
        let calls = scan_calls("ternary.qml", text).unwrap();
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0].literal.as_deref(), Some("Full in %1"));
        assert_eq!(calls[1].literal.as_deref(), Some("Empty in %1"));
        assert_eq!(calls[0].arg_count, 1);
        assert_eq!(calls[1].arg_count, 1);
        for call in &calls {
            validate_call_source(call, call.literal.as_deref().unwrap()).unwrap();
        }

        let without_arg = scan_calls(
            "ternary.qml",
            r#"(full ? Translation.tr("Full in %1") : Translation.tr("Empty in %1"))"#,
        )
        .unwrap();
        assert!(without_arg.iter().all(|call| call.arg_count == 0));
        assert!(without_arg
            .iter()
            .all(|call| { validate_call_source(call, call.literal.as_deref().unwrap()).is_err() }));
    }

    #[test]
    fn scanner_skips_js_regex_literals_without_confusing_division() {
        let text = r#"
const quoted = line.match(/users:\(\(\"([^\"]+)\",pid=\d+/);
const slash = /path\\\/with[/'\"]chars/.test(line);
const ratio = total / count / 2;
const real = Translation.tr("After division");
"#;
        let calls = scan_calls("logic.js", text).unwrap();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].literal.as_deref(), Some("After division"));
    }

    #[test]
    fn scanner_balances_dynamic_expressions_and_rejects_invalid_literals() {
        let call = scan_calls(
            "settings.qml",
            "Item { text: Translation.tr(model.pick({x: [1, 2]}).label).arg(value) }",
        )
        .unwrap()
        .pop()
        .unwrap();
        assert_eq!(call.expression, "model.pick({x: [1, 2]}).label");
        assert_eq!(call.arg_count, 1);

        let dynamic_template = scan_calls("main.qml", "Translation.tr(`Hello ${name}`)")
            .unwrap()
            .pop()
            .unwrap();
        assert_eq!(dynamic_template.literal, None);
        assert_eq!(dynamic_template.expression, "`Hello ${name}`");

        for (source, expected) in [
            ("Translation.tr(\"Hello \" + name)", "string literal"),
            ("Translation.tr(foo, bar)", "exactly one argument"),
            ("Translation.tr(foo", "unterminated"),
        ] {
            let error = error_text(scan_calls("main.qml", source));
            assert!(error.starts_with("main.qml:1:"), "{error}");
            assert!(error.contains(expected), "{error}");
        }
    }

    #[test]
    fn dynamic_catalog_is_strict_and_matches_exact_normalized_calls() {
        let bytes = br#"{
  "schemaVersion": 1,
  "declarations": [
    {
      "source": "settings.qml",
      "expression": "modelData.label",
      "sources": ["Element exit", "Element enter"]
    }
  ]
}
"#;
        let catalog = parse_dynamic_catalog(bytes).unwrap();
        assert_eq!(catalog.len(), 1);
        assert_eq!(catalog[0].expression, "modelData.label");
        assert_eq!(catalog[0].sources, ["Element enter", "Element exit"]);

        for invalid in [
            r#"{"schemaVersion":2,"declarations":[]}"#,
            r#"{"schemaVersion":1,"extra":true,"declarations":[]}"#,
            r#"{"schemaVersion":1,"declarations":[{"source":"x.qml","expression":"x","sources":[]}] }"#,
            r#"{"schemaVersion":1,"declarations":[{"source":"x.qml","expression":"x","sources":["A","A"]}] }"#,
            r#"{"schemaVersion":1,"declarations":[{"source":"x.qml","expression":"x","sources":["A"]},{"source":"x.qml","expression":"x","sources":["B"]}] }"#,
            r#"{"schemaVersion":1,"declarations":[{"source":"x.qml","expression":"x","sources":[""]}] }"#,
        ] {
            assert!(
                parse_dynamic_catalog(invalid.as_bytes()).is_err(),
                "{invalid}"
            );
        }

        assert!(is_valid_declaration_source("main.qml"));
        assert!(is_valid_declaration_source("module.json#patches/0/content"));
        assert!(is_valid_declaration_source(
            "module.json#patches/12/content"
        ));
        for source in [
            "module.json#patches//content",
            "module.json#patches/01/content",
            "module.json#patches/x/content",
            "module.json#patches/0/content/extra",
        ] {
            assert!(!is_valid_declaration_source(source), "{source}");
        }
    }

    #[test]
    fn source_placeholders_cover_empty_boundaries_gaps_and_arg_counts() {
        assert_eq!(placeholder_profile("Plain text").unwrap().max_index, 0);
        assert_eq!(
            placeholder_profile("%1 then %2 and %1").unwrap().max_index,
            2
        );
        assert!(placeholder_profile("").is_err());
        assert!(placeholder_profile(" padded ").is_err());
        assert!(placeholder_profile("line\nfeed").is_err());
        assert!(placeholder_profile("plural %n").is_err());
        assert!(placeholder_profile("zero %0").is_err());
        assert!(placeholder_profile("noncanonical %01").is_err());
        assert!(placeholder_profile("large %100").is_err());
        assert!(placeholder_profile("gap %1 %3").is_err());

        let call = CallSite {
            source: "main.qml".into(),
            line: 2,
            column: 4,
            expression: "\"Needs %1\"".into(),
            literal: Some("Needs %1".into()),
            arg_count: 0,
        };
        assert!(error_text(validate_call_source(&call, "Needs %1")).contains("1 immediate .arg"));
    }

    #[test]
    fn dictionary_requires_shape_content_format_completeness_and_placeholder_parity() {
        let sources = BTreeSet::from(["Count %1".to_string(), "Ready".to_string()]);
        let good = "{\n  \"Count %1\": \"%1 items\",\n  \"Ready\": \"Ready translated\"\n}\n";
        let report = validate_dictionary("zh_TW", good.as_bytes(), &sources, false).unwrap();
        assert!(report.warnings.is_empty());
        let reordered_sources = BTreeSet::from(["Pair %1 %2".to_string()]);
        let reordered = b"{\n  \"Pair %1 %2\": \"%2 then %1\"\n}\n";
        validate_dictionary("zh_TW", reordered, &reordered_sources, false).unwrap();

        for (bytes, expected) in [
            (b"[]\n".as_slice(), "JSON object"),
            (b"{\"Count %1\":1,\"Ready\":\"ok\"}\n", "string-to-string"),
            (
                b"{\"Count %1\":\"%1 items\",\"Count %1\":\"again %1\",\"Ready\":\"ok\"}\n",
                "duplicate dictionary key",
            ),
            (
                b"{\n  \"Count %1\": \"%2 items\",\n  \"Ready\": \"ok\"\n}\n",
                "placeholder",
            ),
            (
                b"{\n  \"Count %1\": \"%1 %1 items\",\n  \"Ready\": \"ok\"\n}\n",
                "placeholder",
            ),
            (
                b"{\n  \"Count %1\": \"%1 items\",\n  \"Ready\": \" \"\n}\n",
                "non-empty",
            ),
            (
                b"{\n  \"Count %1\": \"%1 items\",\n  \"Ready\": \"TODO:\"\n}\n",
                "placeholder marker",
            ),
            (b"{\n  \"Ready\": \"ok\"\n}\n", "missing key"),
            (
                b"{\"Count %1\": \"%1 items\", \"Ready\": \"ok\"}\n",
                "format",
            ),
        ] {
            let error = error_text(validate_dictionary("zh_TW", bytes, &sources, false));
            assert!(error.contains(expected), "{error}");
        }

        let orphan = b"{\n  \"Count %1\": \"%1 items\",\n  \"Orphan\": \"extra\",\n  \"Ready\": \"Ready\"\n}\n";
        let report = validate_dictionary("zh_TW", orphan, &sources, false).unwrap();
        assert_eq!(report.warnings.len(), 2);
        assert!(validate_dictionary("zh_TW", orphan, &sources, true).is_err());
    }
}
