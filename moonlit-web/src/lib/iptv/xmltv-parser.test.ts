import { describe, expect, it } from 'vitest';
import { parseXMLTV, parseXmltvTime } from './xmltv-parser';

function xmltv(body: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE tv SYSTEM "xmltv.dtd"><tv>${body}</tv>`;
}

describe('parseXMLTV', () => {
  it('parses a basic document with one channel and one programme', () => {
    const xml = xmltv(`
      <channel id="ch1"><display-name>BBC One</display-name></channel>
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title>News at Noon</title>
      </programme>
    `);
    const result = parseXMLTV(xml);
    expect(result.programs).toHaveLength(1);
    expect(result.programs[0].title).toBe('News at Noon');
    expect(result.programs[0].channelTvgId).toBe('ch1');
    expect(result.channelMeta['ch1']!.displayName).toBe('BBC One');
  });

  it('returns empty result for empty input', () => {
    const result = parseXMLTV('');
    expect(result.programs).toEqual([]);
    expect(result.channelMeta).toEqual({});
  });
});

describe('parseXmltvTime', () => {
  it('parses with positive timezone offset (+0100)', () => {
    const ms = parseXmltvTime('20250101120000 +0100');
    const d = new Date(ms);
    expect(d.getUTCHours()).toBe(11);
    expect(d.getUTCMinutes()).toBe(0);
  });

  it('parses without timezone as UTC', () => {
    const ms = parseXmltvTime('20250101120000');
    const d = new Date(ms);
    expect(d.getUTCHours()).toBe(12);
    expect(d.getUTCMinutes()).toBe(0);
  });

  it('returns NaN for invalid input', () => {
    expect(parseXmltvTime('not-a-date')).toBeNaN();
    expect(parseXmltvTime('')).toBeNaN();
    expect(parseXmltvTime('2025')).toBeNaN();
  });

  it('parses with negative timezone offset (-0500)', () => {
    const ms = parseXmltvTime('20250101120000 -0500');
    const d = new Date(ms);
    expect(d.getUTCHours()).toBe(17);
    expect(d.getUTCMinutes()).toBe(0);
  });
});

describe('programme parsing details', () => {
  it('decodes CDATA-wrapped title', () => {
    const xml = xmltv(`
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title><![CDATA[Breaking News]]></title>
      </programme>
    `);
    const result = parseXMLTV(xml);
    expect(result.programs[0].title).toBe('Breaking News');
  });

  it('decodes HTML entities in title', () => {
    const xml = xmltv(`
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title>&lt;b&gt;Bold Title&lt;/b&gt;</title>
      </programme>
    `);
    const result = parseXMLTV(xml);
    expect(result.programs[0].title).toBe('<b>Bold Title</b>');
  });

  it('decodes numeric entities', () => {
    const xml = xmltv(`
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title>&#8220;Quoted&#8221; &#x2014; dash</title>
      </programme>
    `);
    const result = parseXMLTV(xml);
    expect(result.programs[0].title).toBe('\u201CQuoted\u201D \u2014 dash');
  });

  it('parses additional programme fields', () => {
    const xml = xmltv(`
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title>Full Show</title>
        <desc>A description of the show.</desc>
        <category>Entertainment</category>
        <icon src="https://example.com/icon.png" />
      </programme>
    `);
    const result = parseXMLTV(xml);
    const p = result.programs[0];
    expect(p.title).toBe('Full Show');
    expect(p.description).toBe('A description of the show.');
    expect(p.category).toBe('Entertainment');
    expect(p.iconUrl).toBe('https://example.com/icon.png');
  });
});

describe('multiple programmes and channels', () => {
  it('handles multiple programmes across two channels', () => {
    const xml = xmltv(`
      <channel id="ch1"><display-name>Channel One</display-name></channel>
      <channel id="ch2"><display-name>Channel Two</display-name></channel>
      <programme start="20250101120000 +0000" stop="20250101130000 +0000" channel="ch1">
        <title>Ch1 Show 1</title>
      </programme>
      <programme start="20250101130000 +0000" stop="20250101140000 +0000" channel="ch1">
        <title>Ch1 Show 2</title>
      </programme>
      <programme start="20250101120000 +0000" stop="20250101133000 +0000" channel="ch2">
        <title>Ch2 Movie</title>
      </programme>
    `);
    const result = parseXMLTV(xml);
    expect(result.programs).toHaveLength(3);
    const ch1 = result.programs.filter((p) => p.channelTvgId === 'ch1');
    const ch2 = result.programs.filter((p) => p.channelTvgId === 'ch2');
    expect(ch1).toHaveLength(2);
    expect(ch2).toHaveLength(1);
    expect(Object.keys(result.channelMeta)).toHaveLength(2);
  });
});

describe('channel with display-name and icon', () => {
  it('extracts display-name and icon from channel', () => {
    const xml = xmltv(`
      <channel id="cnn">
        <display-name>CNN</display-name>
        <icon src="https://example.com/cnn.png" />
      </channel>
    `);
    const result = parseXMLTV(xml);
    expect(result.channelMeta['cnn']!.displayName).toBe('CNN');
    expect(result.channelMeta['cnn']!.icon).toBe('https://example.com/cnn.png');
  });
});
