import { describe, expect, it } from 'vitest';
import { parseM3U, deriveEpgUrls } from './m3u-parser';
import type { IPTVChannel } from './models';

function firstCh(results: IPTVChannel[], idx: number): IPTVChannel {
  const c = results[idx];
  if (!c) throw new Error(`No channel at index ${idx}`);
  return c;
}

describe('parseM3U', () => {
  it('parses a basic M3U playlist with multiple channels', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="bbcone" tvg-name="BBC One" tvg-logo="http://logo/bbc1.png" group-title="UK",BBC One',
      'http://stream.example.com/bbc1.m3u8',
      '#EXTINF:-1 tvg-id="bbctwo" tvg-name="BBC Two" tvg-logo="http://logo/bbc2.png" group-title="UK",BBC Two',
      'http://stream.example.com/bbc2.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(2);

    expect(firstCh(results, 0)).toMatchObject({
      id: 'test::bbcone::0',
      tvgId: 'bbcone',
      name: 'BBC One',
      logo: 'http://logo/bbc1.png',
      group: 'UK',
      url: 'http://stream.example.com/bbc1.m3u8',
    });

    expect(firstCh(results, 1)).toMatchObject({
      id: 'test::bbctwo::1',
      tvgId: 'bbctwo',
      name: 'BBC Two',
      logo: 'http://logo/bbc2.png',
      group: 'UK',
      url: 'http://stream.example.com/bbc2.m3u8',
    });
  });

  it('handles #EXTGRP sticky group', () => {
    const text = [
      '#EXTM3U',
      '#EXTGRP:UK Channels',
      '#EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One",BBC One',
      'http://stream.example.com/bbc1.m3u8',
      '#EXTINF:-1 tvg-id="bbc2" tvg-name="BBC Two",BBC Two',
      'http://stream.example.com/bbc2.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(2);
    expect(firstCh(results, 0).group).toBe('UK Channels');
    expect(firstCh(results, 1).group).toBe('UK Channels');
  });

  it('picks up EXTGRP on the same entry as the pending EXTINF', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="cnn" tvg-name="CNN",CNN',
      '#EXTGRP:News',
      'http://stream.example.com/cnn.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).group).toBe('News');
  });

  it('captures #EXTVLCOPT user-agent and referrer as parser headers', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="stream1" tvg-name="Stream One",Stream One',
      '#EXTVLCOPT:http-user-agent=VLC/3.0',
      '#EXTVLCOPT:http-referrer=https://example.com',
      'http://stream.example.com/stream.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).headers).toEqual({
      'User-Agent': 'VLC/3.0',
      Referer: 'https://example.com',
    });
  });

  it('parses pipe-delimited URL params into parser headers', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="pipe1" tvg-name="Pipe Test",Pipe Test',
      'http://stream.example.com/stream.m3u8|User-Agent=MyAgent&Referer=https://ref.example.com',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).headers).toEqual({
      'User-Agent': 'MyAgent',
      Referer: 'https://ref.example.com',
    });
  });

  it('parses pipe-delimited cookie param into parser headers', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="cookie1" tvg-name="Cookie Test",Cookie Test',
      'http://stream.example.com/stream.m3u8|User-Agent=MyAgent&Cookie=session%3Dabc123',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).headers).toEqual({
      'User-Agent': 'MyAgent',
      Cookie: 'session=abc123',
    });
  });

  it('favours EXTVLCOPT header values over pipe-delimited ones', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="priority1" tvg-name="Priority Test",Priority Test',
      '#EXTVLCOPT:http-user-agent=VLC-Agent',
      'http://stream.example.com/stream.m3u8|User-Agent=PipeAgent',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).headers).toEqual({
      'User-Agent': 'VLC-Agent',
    });
  });

  it('handles referrer (double-r) pipe param variant', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="doubler" tvg-name="Double R Test",Double R Test',
      'http://stream.example.com/stream.m3u8|referrer=https://doubler.example.com',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).headers).toEqual({
      Referer: 'https://doubler.example.com',
    });
  });

  it('filters out decorative/separator rows (all non-alphanumeric characters)', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One",BBC One',
      'http://stream.example.com/bbc1.m3u8',
      '#EXTINF:-1 tvg-name="──────────",──────────',
      'http://stream.example.com/sep.m3u8',
      '#EXTINF:-1 tvg-id="itv" tvg-name="ITV",ITV',
      'http://stream.example.com/itv.m3u8',
      '#EXTINF:-1 tvg-name="━━━━━━━━",━━━━━━━━',
      'http://stream.example.com/sep2.m3u8',
      '#EXTINF:-1 tvg-id="sky1" tvg-name="Sky One",Sky One',
      'http://stream.example.com/sky1.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(3);
    expect(firstCh(results, 0).name).toBe('BBC One');
    expect(firstCh(results, 1).name).toBe('ITV');
    expect(firstCh(results, 2).name).toBe('Sky One');
  });

  it('handles M3U with BOM prefix', () => {
    const text = '\uFEFF' + [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="bom1" tvg-name="BOM Channel",BOM Channel',
      'http://stream.example.com/bom.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('bom1');
    expect(firstCh(results, 0).name).toBe('BOM Channel');
  });

  it('handles CRLF line endings', () => {
    const lines = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="crlf1" tvg-name="CRLF Channel",CRLF Channel',
      'http://stream.example.com/crlf.m3u8',
    ];
    const text = lines.join('\r\n') + '\r\n';

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('crlf1');
  });

  it('uses URL as title when no EXTINF precedes the URL', () => {
    const text = [
      '#EXTM3U',
      'http://stream.example.com/nometa.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).name).toBe('http://stream.example.com/nometa.m3u8');
    expect(firstCh(results, 0).url).toBe('http://stream.example.com/nometa.m3u8');
  });

  it('handles channels with catchup attributes', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="catchup1" tvg-name="Catchup TV" catchup="append" catchup-source="http://catchup.example.com/ts?utc={utc}&lutc={lutc}&duration={duration}" catchup-days="7" group-title="UK",Catchup TV',
      'http://stream.example.com/catchup.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0)).toMatchObject({
      catchupType: 'append',
      catchupSource: 'http://catchup.example.com/ts?utc={utc}&lutc={lutc}&duration={duration}',
      catchupDays: 7,
    });
  });

  it('handles channel with tvg-id only (no tvg-name in attrs)', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="noid123" group-title="Movies",No Name Channel',
      'http://stream.example.com/movie.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('noid123');
    expect(firstCh(results, 0).name).toBe('No Name Channel');
    expect(firstCh(results, 0).id).toBe('test::noid123::0');
  });

  it('handles channel with only tvg-chno as identifier', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-chno="101" tvg-name="Channel 101",Channel 101',
      'http://stream.example.com/ch101.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('101');
  });

  it('returns empty array for empty input', () => {
    expect(parseM3U('', 'test')).toEqual([]);
  });

  it('returns empty array for whitespace-only input', () => {
    expect(parseM3U('  \n  \n  ', 'test')).toEqual([]);
  });

  it('returns empty array for playlist with only header', () => {
    expect(parseM3U('#EXTM3U', 'test')).toEqual([]);
  });

  it('assigns group from group attribute (not just group-title)', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="altgroup" tvg-name="Alt Group" group="Sports",Alt Group',
      'http://stream.example.com/sports.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).group).toBe('Sports');
  });

  it('uses pending title as id key when no tvg-id or tvg-name is present', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1,First',
      'http://stream.example.com/first.m3u8',
      '#EXTINF:-1,Second',
      'http://stream.example.com/second.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(2);
    expect(firstCh(results, 0).id).toBe('test::First::0');
    expect(firstCh(results, 1).id).toBe('test::Second::1');
    expect(firstCh(results, 0).name).toBe('First');
    expect(firstCh(results, 1).name).toBe('Second');
  });

  it('skips KODIPROP lines', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="koditest" tvg-name="Kodi Channel",Kodi Channel',
      '#KODIPROP:inputstreamaddon=inputstream.adaptive',
      '#KODIPROP:inputstream.adaptive.manifest_type=mpd',
      'http://stream.example.com/kodi.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('koditest');
    expect(firstCh(results, 0).url).toBe('http://stream.example.com/kodi.m3u8');
  });

  it('skips comment lines starting with #', () => {
    const text = [
      '#EXTM3U',
      '# This is a comment',
      '#EXTINF:-1 tvg-id="commtest" tvg-name="Comment Test",Comment Test',
      'http://stream.example.com/comm.m3u8',
      '# Another comment',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).tvgId).toBe('commtest');
  });

  it('uses logo attribute as fallback for tvg-logo', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="logotest" tvg-name="Logo Test" logo="http://fallback-logo.png",Logo Test',
      'http://stream.example.com/logo.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).logo).toBe('http://fallback-logo.png');
  });

  it('favours tvg-logo over logo attribute', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="logoprio" tvg-name="Logo Prio" tvg-logo="http://tvg-logo.png" logo="http://logo-attr.png",Logo Prio',
      'http://stream.example.com/logoprio.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).logo).toBe('http://tvg-logo.png');
  });

  it('handles catchup-type as alias for catchup', () => {
    const text = [
      '#EXTM3U',
      '#EXTINF:-1 tvg-id="catchtype" tvg-name="Catch Type" catchup-type="flussonic",Catch Type',
      'http://stream.example.com/catchtype.m3u8',
    ].join('\n');

    const results = parseM3U(text, 'test');

    expect(results).toHaveLength(1);
    expect(firstCh(results, 0).catchupType).toBe('flussonic');
  });
});

describe('deriveEpgUrls', () => {
  it('returns EPG URLs for get.php with username/password', () => {
    const result = deriveEpgUrls('http://xtream.example.com/get.php?username=user123&password=pass456');

    expect(result).toEqual([
      'http://xtream.example.com/xmltv.php?username=user123&password=pass456',
      'http://xtream.example.com/get.php?username=user123&password=pass456&type=epg',
    ]);
  });

  it('returns EPG URLs for player_api.php with username/password', () => {
    const result = deriveEpgUrls('https://server.example.com/player_api.php?username=alice&password=secret');

    expect(result).toEqual([
      'https://server.example.com/xmltv.php?username=alice&password=secret',
      'https://server.example.com/get.php?username=alice&password=secret&type=epg',
    ]);
  });

  it('handles default ports (no port in URL)', () => {
    const result = deriveEpgUrls('https://server.example.com/get.php?username=u&password=p');

    expect(result).toEqual([
      'https://server.example.com/xmltv.php?username=u&password=p',
      'https://server.example.com/get.php?username=u&password=p&type=epg',
    ]);
  });

  it('returns empty array for non-Xtream URLs', () => {
    const result = deriveEpgUrls('http://example.com/playlist.m3u');

    expect(result).toEqual([]);
  });

  it('returns empty array for get.php without username/password', () => {
    const result = deriveEpgUrls('http://server.example.com:8080/get.php');

    expect(result).toEqual([]);
  });

  it('returns empty array for invalid URL', () => {
    const result = deriveEpgUrls('not-a-valid-url');

    expect(result).toEqual([]);
  });
});
