use zeroize::Zeroizing;

use crate::{Error, Result};

const START: &str = "[@bubl ";

#[derive(Debug)]
pub struct ParsedPrompt {
    segments: Vec<String>,
    secrets: Vec<Zeroizing<String>>,
}

impl ParsedPrompt {
    pub fn secrets(&self) -> impl Iterator<Item = &[u8]> {
        self.secrets.iter().map(|value| value.as_bytes())
    }

    pub fn secret_count(&self) -> usize {
        self.secrets.len()
    }

    pub fn render(self, tokens: &[String]) -> Result<String> {
        if tokens.len() != self.secrets.len() {
            return Err(Error::InvalidInput(
                "marker/token count mismatch".to_string(),
            ));
        }

        let mut output = String::new();
        for (index, segment) in self.segments.into_iter().enumerate() {
            output.push_str(&segment);
            if let Some(token) = tokens.get(index) {
                output.push_str("[@bubl-ref ");
                output.push_str(token);
                output.push(']');
            }
        }
        Ok(output)
    }
}

pub fn parse(input: &str) -> Result<Option<ParsedPrompt>> {
    let mut search_cursor = 0;
    let mut literal_cursor = 0;
    let mut segments = Vec::new();
    let mut secrets = Vec::new();

    while let Some(relative) = input[search_cursor..].find("[@bubl") {
        let start = search_cursor + relative;
        let after_name = start + "[@bubl".len();
        let next = input[after_name..].chars().next();

        match next {
            Some(' ') => {}
            Some(']') | None => return Err(malformed()),
            _ => {
                search_cursor = after_name;
                continue;
            }
        }

        segments.push(input[literal_cursor..start].to_string());
        let value_start = start + START.len();
        let (secret, end) = parse_value(input, value_start)?;
        secrets.push(Zeroizing::new(secret));
        search_cursor = end;
        literal_cursor = end;
    }

    if secrets.is_empty() {
        return Ok(None);
    }

    segments.push(input[literal_cursor..].to_string());
    Ok(Some(ParsedPrompt { segments, secrets }))
}

fn parse_value(input: &str, mut cursor: usize) -> Result<(String, usize)> {
    let mut value = String::new();

    while cursor < input.len() {
        let ch = input[cursor..]
            .chars()
            .next()
            .expect("valid character boundary");
        let width = ch.len_utf8();
        match ch {
            '\n' | '\r' | '\0' => return Err(malformed()),
            ']' => {
                if value.is_empty() {
                    return Err(malformed());
                }
                return Ok((value, cursor + width));
            }
            '\\' => {
                let next_index = cursor + width;
                if next_index >= input.len() {
                    value.push('\\');
                    cursor = next_index;
                    continue;
                }
                let next = input[next_index..]
                    .chars()
                    .next()
                    .expect("valid character boundary");
                if matches!(next, ']' | '\\') {
                    value.push(next);
                    cursor = next_index + next.len_utf8();
                } else {
                    value.push('\\');
                    cursor = next_index;
                }
            }
            _ => {
                value.push(ch);
                cursor += width;
            }
        }
    }

    Err(malformed())
}

fn malformed() -> Error {
    Error::InvalidInput("malformed [@bubl …] marker".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordinary_text_is_untouched() {
        assert!(parse("hello [@bubl-ref token]").unwrap().is_none());
    }

    #[test]
    fn marker_like_prefix_does_not_drop_literal_text() {
        let parsed = parse("keep [@bublish x] then [@bubl secret]")
            .unwrap()
            .unwrap();
        assert_eq!(
            parsed.render(&["b1_token".into()]).unwrap(),
            "keep [@bublish x] then [@bubl-ref b1_token]"
        );
    }

    #[test]
    fn parses_and_renders_multiple_markers() {
        let parsed = parse("use [@bubl alpha] and [@bubl βeta]")
            .unwrap()
            .unwrap();
        assert_eq!(parsed.secret_count(), 2);
        assert_eq!(
            parsed.render(&["b1_one".into(), "b1_two".into()]).unwrap(),
            "use [@bubl-ref b1_one] and [@bubl-ref b1_two]"
        );
    }

    #[test]
    fn preserves_whitespace_after_delimiter() {
        let parsed = parse("[@bubl  padded ]").unwrap().unwrap();
        assert_eq!(parsed.secrets().next().unwrap(), b" padded ");
    }

    #[test]
    fn supports_only_documented_escapes() {
        let parsed = parse(r"[@bubl a\]b\\c\qd]").unwrap().unwrap();
        assert_eq!(parsed.secrets().next().unwrap(), br"a]b\c\qd");
    }

    #[test]
    fn rejects_empty_multiline_and_unterminated_markers() {
        for input in ["[@bubl ]", "[@bubl a\nb]", "[@bubl secret", "[@bubl]"] {
            assert!(parse(input).is_err(), "{input:?}");
        }
    }

    #[test]
    fn malformed_later_marker_rejects_the_entire_prompt() {
        assert!(parse("[@bubl valid] then [@bubl broken").is_err());
    }
}
