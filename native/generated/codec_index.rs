// 此文件由 tool/export_codec_data.py 自动生成，请勿手动修改。
// SPDX-FileCopyrightText: 2026 沉默の金 <cmzj@cmzj.org>
// SPDX-FileCopyrightText: 2001 Python Software Foundation
// SPDX-License-Identifier: MIT AND PSF-2.0

pub const NATIVE_ABI_VERSION: u32 = 3;

pub const CANONICAL_NAMES: [&str; 103] = [
    "ascii",
    "big5",
    "big5hkscs",
    "cp037",
    "cp1006",
    "cp1026",
    "cp1125",
    "cp1140",
    "cp273",
    "cp424",
    "cp437",
    "cp500",
    "cp720",
    "cp737",
    "cp775",
    "cp850",
    "cp852",
    "cp855",
    "cp856",
    "cp857",
    "cp858",
    "cp860",
    "cp861",
    "cp862",
    "cp863",
    "cp864",
    "cp865",
    "cp866",
    "cp869",
    "cp874",
    "cp875",
    "cp932",
    "cp949",
    "cp950",
    "euc-jis-2004",
    "euc-jisx0213",
    "euc-jp",
    "euc-kr",
    "gb18030",
    "gb2312",
    "gbk",
    "hp-roman8",
    "hz-gb-2312",
    "iso-2022-jp",
    "iso-2022-kr",
    "iso-8859-1",
    "iso-8859-10",
    "iso-8859-11",
    "iso-8859-13",
    "iso-8859-14",
    "iso-8859-15",
    "iso-8859-16",
    "iso-8859-2",
    "iso-8859-3",
    "iso-8859-4",
    "iso-8859-5",
    "iso-8859-6",
    "iso-8859-7",
    "iso-8859-8",
    "iso-8859-9",
    "iso2022-jp-1",
    "iso2022-jp-2",
    "iso2022-jp-2004",
    "iso2022-jp-3",
    "iso2022-jp-ext",
    "johab",
    "koi8-r",
    "koi8-t",
    "koi8-u",
    "kz-1048",
    "mac-arabic",
    "mac-croatian",
    "mac-cyrillic",
    "mac-farsi",
    "mac-greek",
    "mac-iceland",
    "mac-latin2",
    "mac-roman",
    "mac-romanian",
    "mac-turkish",
    "ptcp154",
    "shift-jisx0213",
    "shift_jis",
    "shift_jis_2004",
    "tis-620",
    "utf-16",
    "utf-16-be",
    "utf-16-le",
    "utf-32",
    "utf-32-be",
    "utf-32-le",
    "utf-7",
    "utf-8",
    "utf-8-sig",
    "windows-1250",
    "windows-1251",
    "windows-1252",
    "windows-1253",
    "windows-1254",
    "windows-1255",
    "windows-1256",
    "windows-1257",
    "windows-1258",
];

pub const CODEC_FLAGS: [u8; 103] = [
    2u8, 4u8, 4u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8,
    2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 4u8, 4u8, 4u8, 4u8, 4u8, 4u8, 4u8,
    4u8, 4u8, 4u8, 2u8, 4u8, 4u8, 4u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8,
    2u8, 2u8, 2u8, 4u8, 4u8, 4u8, 4u8, 4u8, 4u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8,
    2u8, 2u8, 2u8, 2u8, 2u8, 4u8, 4u8, 4u8, 2u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 1u8, 2u8,
    2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8,
];

pub const NATIVE_SUPPORTED_BY_CODEC_ID: [bool; 103] = [
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true,
    true, true, true, true, true, true, true,
];

pub const SBCS_CANONICAL_NAMES: [&str; 70] = [
    "ascii",
    "cp037",
    "cp1006",
    "cp1026",
    "cp1125",
    "cp1140",
    "cp273",
    "cp424",
    "cp437",
    "cp500",
    "cp720",
    "cp737",
    "cp775",
    "cp850",
    "cp852",
    "cp855",
    "cp856",
    "cp857",
    "cp858",
    "cp860",
    "cp861",
    "cp862",
    "cp863",
    "cp864",
    "cp865",
    "cp866",
    "cp869",
    "cp874",
    "cp875",
    "hp-roman8",
    "iso-8859-1",
    "iso-8859-10",
    "iso-8859-11",
    "iso-8859-13",
    "iso-8859-14",
    "iso-8859-15",
    "iso-8859-16",
    "iso-8859-2",
    "iso-8859-3",
    "iso-8859-4",
    "iso-8859-5",
    "iso-8859-6",
    "iso-8859-7",
    "iso-8859-8",
    "iso-8859-9",
    "koi8-r",
    "koi8-t",
    "koi8-u",
    "kz-1048",
    "mac-arabic",
    "mac-croatian",
    "mac-cyrillic",
    "mac-farsi",
    "mac-greek",
    "mac-iceland",
    "mac-latin2",
    "mac-roman",
    "mac-romanian",
    "mac-turkish",
    "ptcp154",
    "tis-620",
    "windows-1250",
    "windows-1251",
    "windows-1252",
    "windows-1253",
    "windows-1254",
    "windows-1255",
    "windows-1256",
    "windows-1257",
    "windows-1258",
];

pub const SBCS_FAMILY_INDEX_BY_CODEC_ID: [i16; 103] = [
    0, -1, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
    24, 25, 26, 27, 28, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 29, -1, -1, -1, 30, 31, 32, 33, 34,
    35, 36, 37, 38, 39, 40, 41, 42, 43, 44, -1, -1, -1, -1, -1, -1, 45, 46, 47, 48, 49, 50, 51, 52,
    53, 54, 55, 56, 57, 58, 59, -1, -1, -1, 60, -1, -1, -1, -1, -1, -1, -1, -1, -1, 61, 62, 63, 64,
    65, 66, 67, 68, 69,
];

pub const SBCS_DECODE_OFFSETS: [u32; 70] = [
    0u32, 1032u32, 2064u32, 3096u32, 4128u32, 5160u32, 6192u32, 7224u32, 8256u32, 9288u32,
    10320u32, 11352u32, 12384u32, 13416u32, 14448u32, 15480u32, 16512u32, 17544u32, 18576u32,
    19608u32, 20640u32, 21672u32, 22704u32, 23736u32, 24768u32, 25800u32, 26832u32, 27864u32,
    28896u32, 29928u32, 30960u32, 31992u32, 33024u32, 34056u32, 35088u32, 36120u32, 37152u32,
    38184u32, 39216u32, 40248u32, 41280u32, 42312u32, 43344u32, 44376u32, 45408u32, 46440u32,
    47472u32, 48504u32, 49536u32, 50568u32, 51600u32, 52632u32, 53664u32, 54696u32, 55728u32,
    56760u32, 57792u32, 58824u32, 59856u32, 60888u32, 61920u32, 62952u32, 63984u32, 65016u32,
    66048u32, 67080u32, 68112u32, 69144u32, 70176u32, 71208u32,
];

pub const SBCS_DECODE_LENGTHS: [u32; 70] = [
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
];

pub const SBCS_ENCODE_OFFSETS: [u32; 70] = [
    72240u32, 73784u32, 75328u32, 79944u32, 82512u32, 88152u32, 90720u32, 93288u32, 96880u32,
    104568u32, 106112u32, 111752u32, 117392u32, 123032u32, 127648u32, 132264u32, 136880u32,
    141496u32, 145088u32, 149704u32, 156368u32, 164056u32, 172768u32, 180456u32, 187120u32,
    194808u32, 200448u32, 205064u32, 208656u32, 212248u32, 217888u32, 219432u32, 223024u32,
    225592u32, 229184u32, 232776u32, 236368u32, 240984u32, 244576u32, 248168u32, 251760u32,
    255352u32, 257920u32, 261512u32, 265104u32, 267672u32, 273312u32, 277928u32, 283568u32,
    288184u32, 292800u32, 302536u32, 309200u32, 313816u32, 320480u32, 330216u32, 337904u32,
    348664u32, 358400u32, 368136u32, 372752u32, 375320u32, 380960u32, 385576u32, 391216u32,
    396856u32, 402496u32, 409160u32, 415824u32, 421464u32,
];

pub const SBCS_ENCODE_LENGTHS: [u32; 70] = [
    1544u32, 1544u32, 4616u32, 2568u32, 5640u32, 2568u32, 2568u32, 3592u32, 7688u32, 1544u32,
    5640u32, 5640u32, 5640u32, 4616u32, 4616u32, 4616u32, 4616u32, 3592u32, 4616u32, 6664u32,
    7688u32, 8712u32, 7688u32, 6664u32, 7688u32, 5640u32, 4616u32, 3592u32, 3592u32, 5640u32,
    1544u32, 3592u32, 2568u32, 3592u32, 3592u32, 3592u32, 4616u32, 3592u32, 3592u32, 3592u32,
    3592u32, 2568u32, 3592u32, 3592u32, 2568u32, 5640u32, 4616u32, 5640u32, 4616u32, 4616u32,
    9736u32, 6664u32, 4616u32, 6664u32, 9736u32, 7688u32, 10760u32, 9736u32, 9736u32, 4616u32,
    2568u32, 5640u32, 4616u32, 5640u32, 5640u32, 5640u32, 6664u32, 6664u32, 5640u32, 6664u32,
];

pub const MBCS_HOT_CANONICAL_NAMES: [&str; 6] =
    ["big5", "cp932", "euc-jp", "euc-kr", "gbk", "shift_jis"];

pub const MBCS_HOT_FAMILY_INDEX_BY_CODEC_ID: [i16; 103] = [
    -1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, 1, -1, -1, -1, -1, 2, 3, -1, -1, 4, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1,
];

pub const MBCS_HOT_MAX_SEQUENCE_LENGTHS: [u8; 6] = [2u8, 2u8, 3u8, 2u8, 2u8, 2u8];

pub const MBCS_HOT_SINGLE_OFFSETS: [u32; 6] = [
    192272u32, 166672u32, 177936u32, 240400u32, 234256u32, 135952u32,
];

pub const MBCS_HOT_SINGLE_LENGTHS: [u32; 6] =
    [1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32];

pub const MBCS_HOT_DOUBLE_OFFSETS: [u32; 6] = [0u32, 0u32, 0u32, 0u32, 0u32, 0u32];

pub const MBCS_HOT_DOUBLE_LENGTHS: [u32; 6] =
    [90376u32, 56584u32, 80136u32, 91400u32, 129288u32, 40200u32];

pub const MBCS_HOT_TRIPLE_OFFSETS: [u32; 6] = [
    193304u32, 167704u32, 178968u32, 241432u32, 235288u32, 136984u32,
];

pub const MBCS_HOT_TRIPLE_LENGTHS: [u32; 6] = [8u32, 8u32, 48544u32, 8u32, 8u32, 8u32];

pub const MBCS_HOT_ENCODE_OFFSETS: [u32; 6] =
    [90376u32, 56584u32, 80136u32, 91400u32, 129288u32, 40200u32];

pub const MBCS_HOT_ENCODE_LENGTHS: [u32; 6] = [
    101896u32, 110088u32, 97800u32, 149000u32, 104968u32, 95752u32,
];

pub const MBCS_COLD_CANONICAL_NAMES: [&str; 9] = [
    "big5hkscs",
    "cp949",
    "cp950",
    "euc-jis-2004",
    "euc-jisx0213",
    "gb2312",
    "johab",
    "shift-jisx0213",
    "shift_jis_2004",
];

pub const MBCS_COLD_FAMILY_INDEX_BY_CODEC_ID: [i16; 103] = [
    -1, -1, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, 1, 2, 3, 4, -1, -1, -1, 5, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 6, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, 7, -1, 8, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1,
];

pub const MBCS_COLD_MAX_SEQUENCE_LENGTHS: [u8; 9] = [2u8, 2u8, 2u8, 3u8, 3u8, 2u8, 2u8, 2u8, 2u8];

pub const MBCS_COLD_SINGLE_OFFSETS: [u32; 9] = [
    2059768u32, 2060800u32, 2061832u32, 2062864u32, 2063896u32, 2064928u32, 2065960u32, 2066992u32,
    2068024u32,
];

pub const MBCS_COLD_SINGLE_LENGTHS: [u32; 9] = [
    1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32, 1032u32,
];

pub const MBCS_COLD_DOUBLE_OFFSETS: [u32; 9] = [
    0u32, 123176u32, 250416u32, 340792u32, 438564u32, 536336u32, 619544u32, 734496u32, 796428u32,
];

pub const MBCS_COLD_DOUBLE_LENGTHS: [u32; 9] = [
    123176u32, 127240u32, 90376u32, 97772u32, 97772u32, 83208u32, 114952u32, 61932u32, 61932u32,
];

pub const MBCS_COLD_TRIPLE_OFFSETS: [u32; 9] = [
    2069056u32, 2069064u32, 2069072u32, 2069080u32, 2137112u32, 2205144u32, 2205152u32, 2205160u32,
    2205168u32,
];

pub const MBCS_COLD_TRIPLE_LENGTHS: [u32; 9] =
    [8u32, 8u32, 8u32, 68032u32, 68032u32, 8u32, 8u32, 8u32, 8u32];

pub const MBCS_COLD_ENCODE_OFFSETS: [u32; 9] = [
    858360u32, 1007592u32, 1156592u32, 1258488u32, 1396600u32, 1534704u32, 1634552u32, 1783552u32,
    1921656u32,
];

pub const MBCS_COLD_ENCODE_LENGTHS: [u32; 9] = [
    149232u32, 149000u32, 101896u32, 138112u32, 138104u32, 99848u32, 149000u32, 138104u32,
    138112u32,
];

pub const STATEFUL_NATIVE_FAMILY_INDEX_BY_CODEC_ID: [i16; 103] = [
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 2, 1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 3, 4, 5, 6, 7, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1,
];

pub const ISO2022_SET_IDS: [&str; 11] = [
    "gb2312",
    "iso8859_1_g2",
    "iso8859_7_g2",
    "jisx0201_k",
    "jisx0201_r",
    "jisx0208",
    "jisx0208_o",
    "jisx0212",
    "jisx0213_2",
    "jisx0213_2004_1",
    "ksx1001",
];

pub const ISO2022_SET_DECODE_OFFSETS: [u32; 11] = [
    135200u32, 270400u32, 272464u32, 276576u32, 278640u32, 281728u32, 412832u32, 543936u32,
    827112u32, 669920u32, 976816u32,
];

pub const ISO2022_SET_DECODE_LENGTHS: [u32; 11] = [
    35352u32, 520u32, 520u32, 520u32, 520u32, 35352u32, 35352u32, 35352u32, 35352u32, 35630u32,
    35352u32,
];

pub const ISO2022_SET_ENCODE_OFFSETS: [u32; 11] = [
    170552u32, 270920u32, 272984u32, 277096u32, 279160u32, 317080u32, 448184u32, 579288u32,
    862464u32, 705552u32, 1012168u32,
];

pub const ISO2022_SET_ENCODE_LENGTHS: [u32; 11] = [
    99848u32, 1544u32, 3592u32, 1544u32, 2568u32, 95752u32, 95752u32, 90632u32, 114352u32,
    121560u32, 149000u32,
];

pub const ISO2022_SET_WIDTHS: [u8; 11] = [2u8, 1u8, 1u8, 1u8, 1u8, 2u8, 2u8, 2u8, 2u8, 2u8, 2u8];

pub const ISO2022_SET_IS_G2: [u8; 11] = [0u8, 1u8, 1u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8];

pub const ISO2022_JP_CANONICAL_NAMES: [&str; 6] = [
    "iso-2022-jp",
    "iso2022-jp-1",
    "iso2022-jp-2",
    "iso2022-jp-2004",
    "iso2022-jp-3",
    "iso2022-jp-ext",
];

pub const ISO2022_JP_FAMILY_INDEX_BY_CODEC_ID: [i16; 103] = [
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 1, 2, 3, 4, 5, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1,
];

pub const ISO2022_JP_CODEC_SET_ORDER_OFFSETS: [u16; 6] = [0u16, 3u16, 7u16, 15u16, 18u16, 20u16];

pub const ISO2022_JP_CODEC_SET_ORDER_LENGTHS: [u8; 6] = [3u8, 4u8, 8u8, 3u8, 2u8, 5u8];

pub const ISO2022_JP_CODEC_SET_ORDER_VALUES: [u8; 25] = [
    5u8, 4u8, 6u8, 5u8, 7u8, 4u8, 6u8, 5u8, 7u8, 10u8, 0u8, 4u8, 6u8, 1u8, 2u8, 5u8, 9u8, 8u8, 5u8,
    8u8, 5u8, 7u8, 4u8, 3u8, 6u8,
];

pub const GB18030_DOUBLE_DECODE_OFFSET: u32 = 0u32;
pub const GB18030_DOUBLE_DECODE_LENGTH: u32 = 262152u32;
pub const GB18030_DOUBLE_ENCODE_OFFSET: u32 = 262152u32;
pub const GB18030_DOUBLE_ENCODE_LENGTH: u32 = 132616u32;
pub const GB18030_RANGES_OFFSET: u32 = 394768u32;
pub const GB18030_RANGES_LENGTH: u32 = 2476u32;

pub const HZ_DECODE_OFFSET: u32 = 0u32;
pub const HZ_DECODE_LENGTH: u32 = 35352u32;
pub const HZ_ENCODE_OFFSET: u32 = 35352u32;
pub const HZ_ENCODE_LENGTH: u32 = 99848u32;

pub const ISO2022_KR_DECODE_OFFSET: u32 = 1161168u32;
pub const ISO2022_KR_DECODE_LENGTH: u32 = 35352u32;
pub const ISO2022_KR_ENCODE_OFFSET: u32 = 1196520u32;
pub const ISO2022_KR_ENCODE_LENGTH: u32 = 149000u32;

pub fn canonical_name(codec_id: u32) -> &'static str {
    CANONICAL_NAMES[codec_id as usize]
}

pub fn is_utf(codec_id: u32) -> bool {
    CODEC_FLAGS
        .get(codec_id as usize)
        .is_some_and(|flags| (flags & 0x1) != 0)
}

pub fn native_supports(codec_id: u32) -> bool {
    NATIVE_SUPPORTED_BY_CODEC_ID
        .get(codec_id as usize)
        .copied()
        .unwrap_or(false)
}

pub fn sbcs_family_index(codec_id: u32) -> Option<usize> {
    let value = SBCS_FAMILY_INDEX_BY_CODEC_ID[codec_id as usize];
    if value < 0 {
        None
    } else {
        Some(value as usize)
    }
}

pub fn mbcs_hot_family_index(codec_id: u32) -> Option<usize> {
    let value = MBCS_HOT_FAMILY_INDEX_BY_CODEC_ID[codec_id as usize];
    if value < 0 {
        None
    } else {
        Some(value as usize)
    }
}

pub fn mbcs_cold_family_index(codec_id: u32) -> Option<usize> {
    let value = MBCS_COLD_FAMILY_INDEX_BY_CODEC_ID[codec_id as usize];
    if value < 0 {
        None
    } else {
        Some(value as usize)
    }
}

pub fn stateful_native_family_index(codec_id: u32) -> Option<usize> {
    let value = STATEFUL_NATIVE_FAMILY_INDEX_BY_CODEC_ID[codec_id as usize];
    if value < 0 {
        None
    } else {
        Some(value as usize)
    }
}

pub fn iso2022_jp_family_index(codec_id: u32) -> Option<usize> {
    let value = ISO2022_JP_FAMILY_INDEX_BY_CODEC_ID[codec_id as usize];
    if value < 0 {
        None
    } else {
        Some(value as usize)
    }
}
