use url::Url;

#[derive(Debug, PartialEq)]
pub struct DeepLink {
    pub action: String,
    pub params: Vec<(String, String)>,
}

pub fn parse(raw: &str) -> Option<DeepLink> {
    let url = Url::parse(raw).ok()?;
    if url.scheme() != "moonlit" {
        return None;
    }
    let action = url.host_str()?.to_string();
    let params = url
        .query_pairs()
        .map(|(k, v)| (k.into_owned(), v.into_owned()))
        .collect();
    Some(DeepLink { action, params })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_trakt_callback() {
        let link = parse("moonlit://trakt-callback?code=abc123&state=xyz").unwrap();
        assert_eq!(link.action, "trakt-callback");
        assert_eq!(
            link.params,
            vec![
                ("code".to_string(), "abc123".to_string()),
                ("state".to_string(), "xyz".to_string())
            ]
        );
    }

    #[test]
    fn rejects_other_schemes() {
        assert_eq!(parse("https://example.com/x"), None);
    }

    #[test]
    fn rejects_garbage() {
        assert_eq!(parse("not a url"), None);
    }
}
