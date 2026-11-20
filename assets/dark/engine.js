/**
 * PageReader 深色注入引擎 —— 骨架部分。
 *
 * 算法部分（颜色解析、亮度映射、极点插值、缓存、CSS 规则遍历）单独生成，
 * 以 `/* @ALGORITHM *\/` 为占位注入到本文件头部。
 *
 * 设计要点：
 *
 * 1. 只做 dynamic 一种模式。不做 filter / static，减少分支。
 * 2. 代码容器、数学公式、媒体元素一律跳过算色 —— 不是选项，是硬规则。
 * 3. 占位样式先于算色生效，避免翻页白闪。
 * 4. 遍历有上限，MutationObserver 有节流，避免长文档卡死。
 */
(function () {
  'use strict';

  // ===== 算法部分（颜色解析 / 亮度映射 / 缓存 / CSS 遍历）=====
    const isLayerRuleSupported = typeof CSSLayerBlockRule === "function";

    const isContainerRuleSupported = typeof CSSContainerRule === "function";

    let query = null;

    const isSystemDarkModeEnabled = () =>
        (query || matchMedia("(prefers-color-scheme: dark)")).matches;

    function evalMath(expression) {
        const rpnStack = [];
        const workingStack = [];
        let lastToken;
        for (let i = 0, len = expression.length; i < len; i++) {
            const token = expression[i];
            if (!token || token === " ") {
                continue;
            }
            if (operators.has(token)) {
                const op = operators.get(token);
                while (workingStack.length) {
                    const currentOp = operators.get(workingStack[0]);
                    if (!currentOp) {
                        break;
                    }
                    if (op.lessOrEqualThan(currentOp)) {
                        rpnStack.push(workingStack.shift());
                    } else {
                        break;
                    }
                }
                workingStack.unshift(token);
            } else if (!lastToken || operators.has(lastToken)) {
                rpnStack.push(token);
            } else {
                rpnStack[rpnStack.length - 1] += token;
            }
            lastToken = token;
        }
        rpnStack.push(...workingStack);
        const stack = [];
        for (let i = 0, len = rpnStack.length; i < len; i++) {
            const op = operators.get(rpnStack[i]);
            if (op) {
                const args = stack.splice(0, 2);
                stack.push(op.exec(args[1], args[0]));
            } else {
                stack.unshift(parseFloat(rpnStack[i]));
            }
        }
        return stack[0];
    }

    class Operator {
        precendce;
        execMethod;
        constructor(precedence, method) {
            this.precendce = precedence;
            this.execMethod = method;
        }
        exec(left, right) {
            return this.execMethod(left, right);
        }
        lessOrEqualThan(op) {
            return this.precendce <= op.precendce;
        }
    }

    const operators = new Map([
        ["+", new Operator(1, (left, right) => left + right)],
        ["-", new Operator(1, (left, right) => left - right)],
        ["*", new Operator(2, (left, right) => left * right)],
        ["/", new Operator(2, (left, right) => left / right)]
    ]);

    function escapeRegExpSpecialChars(input) {
        return input.replaceAll(/[\^$.*+?\(\)\[\]{}|\-\\]/g, "\\/* @ALGORITHM */");
    }

    function getParenthesesRange(input, searchStartIndex = 0) {
        return getOpenCloseRange(input, searchStartIndex, "(", ")", []);
    }

    function getOpenCloseRange(
        input,
        searchStartIndex,
        openToken,
        closeToken,
        excludeRanges
    ) {
        let indexOf;
        if (excludeRanges.length === 0) {
            indexOf = (token, pos) => input.indexOf(token, pos);
        } else {
            indexOf = (token, pos) =>
                indexOfExcluding(input, token, pos, excludeRanges);
        }
        const {length} = input;
        let depth = 0;
        let firstOpenIndex = -1;
        for (let i = searchStartIndex; i < length; i++) {
            if (depth === 0) {
                const openIndex = indexOf(openToken, i);
                if (openIndex < 0) {
                    break;
                }
                firstOpenIndex = openIndex;
                depth++;
                i = openIndex;
            } else {
                const closeIndex = indexOf(closeToken, i);
                if (closeIndex < 0) {
                    break;
                }
                const openIndex = indexOf(openToken, i);
                if (openIndex < 0 || closeIndex <= openIndex) {
                    depth--;
                    if (depth === 0) {
                        return {start: firstOpenIndex, end: closeIndex + 1};
                    }
                    i = closeIndex;
                } else {
                    depth++;
                    i = openIndex;
                }
            }
        }
        return null;
    }

    function indexOfExcluding(input, search, position, excludeRanges) {
        const i = input.indexOf(search, position);
        const exclusion = excludeRanges.find((r) => i >= r.start && i < r.end);
        if (exclusion) {
            return indexOfExcluding(
                input,
                search,
                exclusion.end,
                excludeRanges
            );
        }
        return i;
    }

    const hslaParseCache = new Map();

    const rgbaParseCache = new Map();

    function parseColorWithCache($color) {
        $color = $color.trim();
        const key = $color;
        if (rgbaParseCache.has(key)) {
            return rgbaParseCache.get(key);
        }
        if ($color.includes("calc(")) {
            $color = lowerCalcExpression($color);
        }
        const color = parse($color);
        rgbaParseCache.set(key, color);
        return color;
    }

    function parseToHSLWithCache(color) {
        if (hslaParseCache.has(color)) {
            return hslaParseCache.get(color);
        }
        const rgb = parseColorWithCache(color);
        if (!rgb) {
            return null;
        }
        const hsl = rgbToHSL(rgb);
        hslaParseCache.set(color, hsl);
        return hsl;
    }

    function clearColorCache() {
        hslaParseCache.clear();
        rgbaParseCache.clear();
    }

    function hslToRGB({h, s, l, a = 1}) {
        if (s === 0) {
            const [r, b, g] = [l, l, l].map((x) => Math.round(x * 255));
            return {r, g, b, a};
        }
        const c = (1 - Math.abs(2 * l - 1)) * s;
        const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
        const m = l - c / 2;
        const [r, g, b] = (
            h < 60
                ? [c, x, 0]
                : h < 120
                  ? [x, c, 0]
                  : h < 180
                    ? [0, c, x]
                    : h < 240
                      ? [0, x, c]
                      : h < 300
                        ? [x, 0, c]
                        : [c, 0, x]
        ).map((n) => Math.round((n + m) * 255));
        return {r, g, b, a};
    }

    function rgbToHSL({r: r255, g: g255, b: b255, a = 1}) {
        const r = r255 / 255;
        const g = g255 / 255;
        const b = b255 / 255;
        const max = Math.max(r, g, b);
        const min = Math.min(r, g, b);
        const c = max - min;
        const l = (max + min) / 2;
        if (c === 0) {
            return {h: 0, s: 0, l, a};
        }
        let h =
            (max === r
                ? ((g - b) / c) % 6
                : max === g
                  ? (b - r) / c + 2
                  : (r - g) / c + 4) * 60;
        if (h < 0) {
            h += 360;
        }
        const s = c / (1 - Math.abs(2 * l - 1));
        return {h, s, l, a};
    }

    function toFixed(n, digits = 0) {
        const fixed = n.toFixed(digits);
        if (digits === 0) {
            return fixed;
        }
        const dot = fixed.indexOf(".");
        if (dot >= 0) {
            const zerosMatch = fixed.match(/0+$/);
            if (zerosMatch) {
                if (zerosMatch.index === dot + 1) {
                    return fixed.substring(0, dot);
                }
                return fixed.substring(0, zerosMatch.index);
            }
        }
        return fixed;
    }

    function rgbToString(rgb) {
        const {r, g, b, a} = rgb;
        if (a != null && a < 1) {
            return `rgba(${toFixed(r)}, ${toFixed(g)}, ${toFixed(b)}, ${toFixed(a, 2)})`;
        }
        return `rgb(${toFixed(r)}, ${toFixed(g)}, ${toFixed(b)})`;
    }

    function rgbToHexString({r, g, b, a}) {
        return `#${(a != null && a < 1
            ? [r, g, b, Math.round(a * 255)]
            : [r, g, b]
        )
            .map((x) => {
                return `${x < 16 ? "0" : ""}${x.toString(16)}`;
            })
            .join("")}`;
    }

    function hslToString(hsl) {
        const {h, s, l, a} = hsl;
        if (a != null && a < 1) {
            return `hsla(${toFixed(h)}, ${toFixed(s * 100)}%, ${toFixed(l * 100)}%, ${toFixed(a, 2)})`;
        }
        return `hsl(${toFixed(h)}, ${toFixed(s * 100)}%, ${toFixed(l * 100)}%)`;
    }

    const rgbMatch = /^rgba?\([^\(\)]+\)$/;

    const hslMatch = /^hsla?\([^\(\)]+\)$/;

    const hexMatch = /^#[0-9a-f]+$/i;

    const supportedColorFuncs = [
        "color",
        "color-mix",
        "hwb",
        "lab",
        "lch",
        "oklab",
        "oklch"
    ];

    function parse($color) {
        const c = $color.trim().toLowerCase();
        if (c.includes("(from ")) {
            if (c.indexOf("(from") !== c.lastIndexOf("(from")) {
                return null;
            }
            return domParseColor(c);
        }
        if (c.match(rgbMatch)) {
            if (c.startsWith("rgb(#") || c.startsWith("rgba(#")) {
                if (c.lastIndexOf("rgb") > 0) {
                    return null;
                }
                return domParseColor(c);
            }
            return parseRGB(c);
        }
        if (c.match(hslMatch)) {
            return parseHSL(c);
        }
        if (c.match(hexMatch)) {
            return parseHex(c);
        }
        if (knownColors.has(c)) {
            return getColorByName(c);
        }
        if (systemColors.has(c)) {
            return getSystemColor(c);
        }
        if (c === "transparent") {
            return {r: 0, g: 0, b: 0, a: 0};
        }
        if (
            c.endsWith(")") &&
            supportedColorFuncs.some(
                (fn) =>
                    c.startsWith(fn) &&
                    c[fn.length] === "(" &&
                    c.lastIndexOf(fn) === 0
            )
        ) {
            return domParseColor(c);
        }
        if (c.startsWith("light-dark(") && c.endsWith(")")) {
            const match = c.match(
                /^light-dark\(\s*([a-z]+(\(.*\))?),\s*([a-z]+(\(.*\))?)\s*\)$/
            );
            if (match) {
                const schemeColor = isSystemDarkModeEnabled()
                    ? match[3]
                    : match[1];
                return parse(schemeColor);
            }
        }
        return null;
    }

    const C_0 = "0".charCodeAt(0);

    const C_9 = "9".charCodeAt(0);

    const C_e = "e".charCodeAt(0);

    const C_DOT = ".".charCodeAt(0);

    const C_PLUS = "+".charCodeAt(0);

    const C_MINUS = "-".charCodeAt(0);

    const C_SPACE = " ".charCodeAt(0);

    const C_COMMA = ",".charCodeAt(0);

    const C_SLASH = "/".charCodeAt(0);

    const C_PERCENT = "%".charCodeAt(0);

    function getNumbersFromString(input, range, units) {
        const numbers = [];
        const searchStart = input.indexOf("(") + 1;
        const searchEnd = input.length - 1;
        let numStart = -1;
        let unitStart = -1;
        const push = (matchEnd) => {
            const numEnd = unitStart > -1 ? unitStart : matchEnd;
            const $num = input.slice(numStart, numEnd);
            let n = parseFloat($num);
            const r = range[numbers.length];
            if (unitStart > -1) {
                const unit = input.slice(unitStart, matchEnd);
                const u = units[unit];
                if (u != null) {
                    n *= r / u;
                }
            }
            if (r > 1) {
                n = Math.round(n);
            }
            numbers.push(n);
            numStart = -1;
            unitStart = -1;
        };
        for (let i = searchStart; i < searchEnd; i++) {
            const c = input.charCodeAt(i);
            const isNumChar =
                (c >= C_0 && c <= C_9) ||
                c === C_DOT ||
                c === C_PLUS ||
                c === C_MINUS ||
                c === C_e;
            const isDelimiter = c === C_SPACE || c === C_COMMA || c === C_SLASH;
            if (isNumChar) {
                if (numStart === -1) {
                    numStart = i;
                }
            } else if (numStart > -1) {
                if (isDelimiter) {
                    push(i);
                } else if (unitStart === -1) {
                    unitStart = i;
                }
            }
        }
        if (numStart > -1) {
            push(searchEnd);
        }
        return numbers;
    }

    const rgbRange = [255, 255, 255, 1];

    const rgbUnits = {"%": 100};

    function getRGBValues(input) {
        const CHAR_CODE_0 = 48;
        const length = input.length;
        let i = 0;
        let digitsCount = 0;
        let digitSequence = false;
        let floatDigitsCount = -1;
        let delimiter = C_SPACE;
        let channel = -1;
        let result = null;
        while (i < length) {
            const c = input.charCodeAt(i);
            if ((c >= C_0 && c <= C_9) || c === C_DOT) {
                if (!digitSequence) {
                    digitSequence = true;
                    digitsCount = 0;
                    floatDigitsCount = -1;
                    channel++;
                    if (channel === 3 && result) {
                        result[3] = 0;
                    }
                    if (channel > 3) {
                        return null;
                    }
                }
                if (c === C_DOT) {
                    if (floatDigitsCount > 0) {
                        return null;
                    }
                    floatDigitsCount = 0;
                } else {
                    const d = c - CHAR_CODE_0;
                    if (!result) {
                        result = [0, 0, 0, 1];
                    }
                    if (floatDigitsCount > -1) {
                        floatDigitsCount++;
                        result[channel] += d / 10 ** floatDigitsCount;
                    } else {
                        digitsCount++;
                        if (digitsCount > 3) {
                            return null;
                        }
                        result[channel] = result[channel] * 10 + d;
                    }
                }
            } else if (c === C_PERCENT) {
                if (
                    channel < 0 ||
                    channel > 3 ||
                    delimiter !== C_SPACE ||
                    !result
                ) {
                    return null;
                }
                result[channel] =
                    channel < 3
                        ? Math.round((result[channel] * 255) / 100)
                        : result[channel] / 100;
                digitSequence = false;
            } else {
                digitSequence = false;
                if (c === C_SPACE) {
                    if (channel === 0) {
                        delimiter = c;
                    }
                } else if (c === C_COMMA) {
                    if (channel === -1) {
                        return null;
                    }
                    delimiter = C_COMMA;
                } else if (c === C_SLASH) {
                    if (channel !== 2 || delimiter !== C_SPACE) {
                        return null;
                    }
                } else {
                    return null;
                }
            }
            i++;
        }
        if (channel < 2 || channel > 3) {
            return null;
        }
        return result;
    }

    function parseRGB($rgb) {
        const [r, g, b, a = 1] = getNumbersFromString($rgb, rgbRange, rgbUnits);
        if (r == null || g == null || b == null || a == null) {
            return null;
        }
        return {r, g, b, a};
    }

    const hslRange = [360, 1, 1, 1];

    const hslUnits = {"%": 100, "deg": 360, "rad": 2 * Math.PI, "turn": 1};

    function parseHSL($hsl) {
        const [h, s, l, a = 1] = getNumbersFromString($hsl, hslRange, hslUnits);
        if (h == null || s == null || l == null || a == null) {
            return null;
        }
        return hslToRGB({h, s, l, a});
    }

    const C_A = "A".charCodeAt(0);

    const C_F = "F".charCodeAt(0);

    const C_a = "a".charCodeAt(0);

    const C_f = "f".charCodeAt(0);

    function parseHex($hex) {
        const length = $hex.length;
        const digitCount = length - 1;
        const isShort = digitCount === 3 || digitCount === 4;
        const isLong = digitCount === 6 || digitCount === 8;
        if (!isShort && !isLong) {
            return null;
        }
        const hex = (i) => {
            const c = $hex.charCodeAt(i);
            if (c >= C_A && c <= C_F) {
                return c + 10 - C_A;
            }
            if (c >= C_a && c <= C_f) {
                return c + 10 - C_a;
            }
            return c - C_0;
        };
        let r;
        let g;
        let b;
        let a = 1;
        if (isShort) {
            r = hex(1) * 17;
            g = hex(2) * 17;
            b = hex(3) * 17;
            if (digitCount === 4) {
                a = (hex(4) * 17) / 255;
            }
        } else {
            r = hex(1) * 16 + hex(2);
            g = hex(3) * 16 + hex(4);
            b = hex(5) * 16 + hex(6);
            if (digitCount === 8) {
                a = (hex(7) * 16 + hex(8)) / 255;
            }
        }
        return {r, g, b, a};
    }

    function getColorByName($color) {
        const n = knownColors.get($color);
        return {
            r: (n >> 16) & 255,
            g: (n >> 8) & 255,
            b: (n >> 0) & 255,
            a: 1
        };
    }

    function getSystemColor($color) {
        const n = systemColors.get($color);
        return {
            r: (n >> 16) & 255,
            g: (n >> 8) & 255,
            b: (n >> 0) & 255,
            a: 1
        };
    }

    function lowerCalcExpression(color) {
        let searchIndex = 0;
        const replaceBetweenIndices = (start, end, replacement) => {
            color =
                color.substring(0, start) + replacement + color.substring(end);
        };
        while ((searchIndex = color.indexOf("calc(")) !== -1) {
            const range = getParenthesesRange(color, searchIndex);
            if (!range) {
                break;
            }
            let slice = color.slice(range.start + 1, range.end - 1);
            const includesPercentage = slice.includes("%");
            slice = slice.split("%").join("");
            const output = Math.round(evalMath(slice));
            replaceBetweenIndices(
                range.start - 4,
                range.end,
                output + (includesPercentage ? "%" : "")
            );
        }
        return color;
    }

    const knownColors = new Map(
        Object.entries({
            aliceblue: 0xf0f8ff,
            antiquewhite: 0xfaebd7,
            aqua: 0x00ffff,
            aquamarine: 0x7fffd4,
            azure: 0xf0ffff,
            beige: 0xf5f5dc,
            bisque: 0xffe4c4,
            black: 0x000000,
            blanchedalmond: 0xffebcd,
            blue: 0x0000ff,
            blueviolet: 0x8a2be2,
            brown: 0xa52a2a,
            burlywood: 0xdeb887,
            cadetblue: 0x5f9ea0,
            chartreuse: 0x7fff00,
            chocolate: 0xd2691e,
            coral: 0xff7f50,
            cornflowerblue: 0x6495ed,
            cornsilk: 0xfff8dc,
            crimson: 0xdc143c,
            cyan: 0x00ffff,
            darkblue: 0x00008b,
            darkcyan: 0x008b8b,
            darkgoldenrod: 0xb8860b,
            darkgray: 0xa9a9a9,
            darkgrey: 0xa9a9a9,
            darkgreen: 0x006400,
            darkkhaki: 0xbdb76b,
            darkmagenta: 0x8b008b,
            darkolivegreen: 0x556b2f,
            darkorange: 0xff8c00,
            darkorchid: 0x9932cc,
            darkred: 0x8b0000,
            darksalmon: 0xe9967a,
            darkseagreen: 0x8fbc8f,
            darkslateblue: 0x483d8b,
            darkslategray: 0x2f4f4f,
            darkslategrey: 0x2f4f4f,
            darkturquoise: 0x00ced1,
            darkviolet: 0x9400d3,
            deeppink: 0xff1493,
            deepskyblue: 0x00bfff,
            dimgray: 0x696969,
            dimgrey: 0x696969,
            dodgerblue: 0x1e90ff,
            firebrick: 0xb22222,
            floralwhite: 0xfffaf0,
            forestgreen: 0x228b22,
            fuchsia: 0xff00ff,
            gainsboro: 0xdcdcdc,
            ghostwhite: 0xf8f8ff,
            gold: 0xffd700,
            goldenrod: 0xdaa520,
            gray: 0x808080,
            grey: 0x808080,
            green: 0x008000,
            greenyellow: 0xadff2f,
            honeydew: 0xf0fff0,
            hotpink: 0xff69b4,
            indianred: 0xcd5c5c,
            indigo: 0x4b0082,
            ivory: 0xfffff0,
            khaki: 0xf0e68c,
            lavender: 0xe6e6fa,
            lavenderblush: 0xfff0f5,
            lawngreen: 0x7cfc00,
            lemonchiffon: 0xfffacd,
            lightblue: 0xadd8e6,
            lightcoral: 0xf08080,
            lightcyan: 0xe0ffff,
            lightgoldenrodyellow: 0xfafad2,
            lightgray: 0xd3d3d3,
            lightgrey: 0xd3d3d3,
            lightgreen: 0x90ee90,
            lightpink: 0xffb6c1,
            lightsalmon: 0xffa07a,
            lightseagreen: 0x20b2aa,
            lightskyblue: 0x87cefa,
            lightslategray: 0x778899,
            lightslategrey: 0x778899,
            lightsteelblue: 0xb0c4de,
            lightyellow: 0xffffe0,
            lime: 0x00ff00,
            limegreen: 0x32cd32,
            linen: 0xfaf0e6,
            magenta: 0xff00ff,
            maroon: 0x800000,
            mediumaquamarine: 0x66cdaa,
            mediumblue: 0x0000cd,
            mediumorchid: 0xba55d3,
            mediumpurple: 0x9370db,
            mediumseagreen: 0x3cb371,
            mediumslateblue: 0x7b68ee,
            mediumspringgreen: 0x00fa9a,
            mediumturquoise: 0x48d1cc,
            mediumvioletred: 0xc71585,
            midnightblue: 0x191970,
            mintcream: 0xf5fffa,
            mistyrose: 0xffe4e1,
            moccasin: 0xffe4b5,
            navajowhite: 0xffdead,
            navy: 0x000080,
            oldlace: 0xfdf5e6,
            olive: 0x808000,
            olivedrab: 0x6b8e23,
            orange: 0xffa500,
            orangered: 0xff4500,
            orchid: 0xda70d6,
            palegoldenrod: 0xeee8aa,
            palegreen: 0x98fb98,
            paleturquoise: 0xafeeee,
            palevioletred: 0xdb7093,
            papayawhip: 0xffefd5,
            peachpuff: 0xffdab9,
            peru: 0xcd853f,
            pink: 0xffc0cb,
            plum: 0xdda0dd,
            powderblue: 0xb0e0e6,
            purple: 0x800080,
            rebeccapurple: 0x663399,
            red: 0xff0000,
            rosybrown: 0xbc8f8f,
            royalblue: 0x4169e1,
            saddlebrown: 0x8b4513,
            salmon: 0xfa8072,
            sandybrown: 0xf4a460,
            seagreen: 0x2e8b57,
            seashell: 0xfff5ee,
            sienna: 0xa0522d,
            silver: 0xc0c0c0,
            skyblue: 0x87ceeb,
            slateblue: 0x6a5acd,
            slategray: 0x708090,
            slategrey: 0x708090,
            snow: 0xfffafa,
            springgreen: 0x00ff7f,
            steelblue: 0x4682b4,
            tan: 0xd2b48c,
            teal: 0x008080,
            thistle: 0xd8bfd8,
            tomato: 0xff6347,
            turquoise: 0x40e0d0,
            violet: 0xee82ee,
            wheat: 0xf5deb3,
            white: 0xffffff,
            whitesmoke: 0xf5f5f5,
            yellow: 0xffff00,
            yellowgreen: 0x9acd32
        })
    );

    const systemColors = new Map(
        Object.entries({
            "ActiveBorder": 0x3b99fc,
            "ActiveCaption": 0x000000,
            "AppWorkspace": 0xaaaaaa,
            "Background": 0x6363ce,
            "ButtonFace": 0xffffff,
            "ButtonHighlight": 0xe9e9e9,
            "ButtonShadow": 0x9fa09f,
            "ButtonText": 0x000000,
            "CaptionText": 0x000000,
            "GrayText": 0x7f7f7f,
            "Highlight": 0xb2d7ff,
            "HighlightText": 0x000000,
            "InactiveBorder": 0xffffff,
            "InactiveCaption": 0xffffff,
            "InactiveCaptionText": 0x000000,
            "InfoBackground": 0xfbfcc5,
            "InfoText": 0x000000,
            "Menu": 0xf6f6f6,
            "MenuText": 0xffffff,
            "Scrollbar": 0xaaaaaa,
            "ThreeDDarkShadow": 0x000000,
            "ThreeDFace": 0xc0c0c0,
            "ThreeDHighlight": 0xffffff,
            "ThreeDLightShadow": 0xffffff,
            "ThreeDShadow": 0x000000,
            "Window": 0xececec,
            "WindowFrame": 0xaaaaaa,
            "WindowText": 0x000000,
            "-webkit-focus-ring-color": 0xe59700
        }).map(([key, value]) => [key.toLowerCase(), value])
    );

    function getSRGBLightness(r, g, b) {
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    }

    function domParseColor($color) {
        if (!context$1) {
            canvas$1 = document.createElement("canvas");
            canvas$1.width = 1;
            canvas$1.height = 1;
            context$1 = canvas$1.getContext("2d", {willReadFrequently: true});
        }
        context$1.fillStyle = $color;
        context$1.fillRect(0, 0, 1, 1);
        const d = context$1.getImageData(0, 0, 1, 1).data;
        const color = `rgba(${d[0]}, ${d[1]}, ${d[2]}, ${(d[3] / 255).toFixed(2)})`;
        return parseRGB(color);
    }

    function scale(x, inLow, inHigh, outLow, outHigh) {
        return ((x - inLow) * (outHigh - outLow)) / (inHigh - inLow) + outLow;
    }

    function clamp(x, min, max) {
        return Math.min(max, Math.max(min, x));
    }

    function multiplyMatrices(m1, m2) {
        const result = [];
        for (let i = 0, len = m1.length; i < len; i++) {
            result[i] = [];
            for (let j = 0, len2 = m2[0].length; j < len2; j++) {
                let sum = 0;
                for (let k = 0, len3 = m1[0].length; k < len3; k++) {
                    sum += m1[i][k] * m2[k][j];
                }
                result[i][j] = sum;
            }
        }
        return result;
    }

    function cachedFactory(factory, size) {
        const cache = new Map();
        return (key) => {
            if (cache.has(key)) {
                return cache.get(key);
            }
            const value = factory(key);
            cache.set(key, value);
            if (cache.size > size) {
                const first = cache.keys().next().value;
                cache.delete(first);
            }
            return value;
        };
    }

    const parsedURLCache = new Map();

    function fixBaseURL($url) {
        if (!anchor) {
            anchor = document.createElement("a");
        }
        anchor.href = $url;
        return anchor.href;
    }

    function parseURL($url, $base = null) {
        const key = `${$url}${$base ? `;${$base}` : ""}`;
        if (parsedURLCache.has(key)) {
            return parsedURLCache.get(key);
        }
        if ($base) {
            const parsedURL = new URL($url, fixBaseURL($base));
            parsedURLCache.set(key, parsedURL);
            return parsedURL;
        }
        const parsedURL = new URL(fixBaseURL($url));
        parsedURLCache.set($url, parsedURL);
        return parsedURL;
    }

    function getAbsoluteURL($base, $relative) {
        if ($relative.match(/^data\\?\:/)) {
            return $relative;
        }
        if (/^\/\//.test($relative)) {
            return `${location.protocol}${$relative}`;
        }
        const b = parseURL($base);
        const a = parseURL($relative, b.href);
        return a.href;
    }

    function getBackgroundPoles(theme) {
        const isDarkScheme = theme.mode === 1;
        const prop = isDarkScheme
            ? "darkSchemeBackgroundColor"
            : "lightSchemeBackgroundColor";
        return [theme[prop], theme.secondaryBackgroundColor];
    }

    function getTextPoles(theme) {
        const isDarkScheme = theme.mode === 1;
        if (isDarkScheme) {
            return [theme.darkSchemeTextColor, theme.secondaryTextColor];
        }
        return [
            theme.lightSchemeTextColor,
            theme.secondaryTextColor || theme.lightSchemeBackgroundColor
        ];
    }

    const DEFAULT_SECONDARY_BG_LIGHTNESS = 0.4;

    function interpolatePoles(t, hsl1, hsl2) {
        const rgb1 = hslToRGB(hsl1);
        const rgb2 = hslToRGB(hsl2);
        const r = Math.round(rgb1.r * (1 - t) + rgb2.r * t);
        const g = Math.round(rgb1.g * (1 - t) + rgb2.g * t);
        const b = Math.round(rgb1.b * (1 - t) + rgb2.b * t);
        const a = (rgb1.a ?? 1) * (1 - t) + (rgb2.a ?? 1) * t;
        return rgbToHSL({r, g, b, a});
    }

    function modifyBgColorExtended(source, pole1, pole2) {
        const {h, s, l, a} = source;
        const hasSecondary = pole2 != null;
        if (!pole2) {
            pole2 = {
                h: pole1.h,
                s: pole1.s,
                l: DEFAULT_SECONDARY_BG_LIGHTNESS,
                a: 1
            };
        }
        const isDark = l < 0.5;
        const isBlue = h > 200 && h < 280;
        const isNeutral = s < 0.12 || (l > 0.8 && isBlue);
        let lx = isDark
            ? scale(l, 0, 0.5, 0, pole2.l)
            : scale(l, 0.5, 1, pole2.l, pole1.l);
        if (isNeutral) {
            if (!hasSecondary) {
                return {h: pole1.h, s: pole1.s, l: lx, a};
            }
            const t = isDark ? l * 2 : (1 - l) * 2;
            const p = interpolatePoles(t, pole1, pole2);
            return {h: p.h, s: p.s, l: lx, a};
        }
        if (isDark) {
            return {h, s, l: lx, a};
        }
        let hx = h;
        const isYellow = h > 60 && h < 180;
        if (isYellow) {
            const isCloserToGreen = h > 120;
            if (isCloserToGreen) {
                hx = scale(h, 120, 180, 135, 180);
            } else {
                hx = scale(h, 60, 120, 60, 105);
            }
        }
        if (hx > 40 && hx < 80) {
            lx *= 0.75;
        }
        return {h: hx, s, l: lx, a};
    }

    function modifyLightSchemeColorExtended(source, poleLight, poleDark) {
        const {h, s, l, a} = source;
        if (!poleDark) {
            poleDark = {h: 0, s: 0, l: 0, a: 1};
        }
        if (poleDark.l > poleLight.l) {
            const pole = poleDark;
            poleDark = poleLight;
            poleLight = pole;
        }
        const isDark = l < 0.5;
        let isNeutral;
        if (isDark) {
            isNeutral = l < 0.2 || s < 0.12;
        } else {
            const isBlue = h > 200 && h < 280;
            isNeutral = s < 0.24 || (l > 0.8 && isBlue);
        }
        const p = interpolatePoles(1 - l, poleLight, poleDark);
        if (isNeutral) {
            return {h: p.h, s: p.s, l: p.l, a};
        }
        return {h, s, l: p.l, a};
    }

    const DEFAULT_SECONDARY_TEXT_LIGHTNESS = 0.55;

    function modifyBlueFgHue(hue) {
        return scale(hue, 205, 245, 205, 220);
    }

    function modifyFgColorExtended(source, pole1, pole2) {
        const {h, s, l, a} = source;
        const hasSecondary = pole2 != null;
        if (!pole2) {
            pole2 = {
                h: pole1.h,
                s: pole1.s,
                l: DEFAULT_SECONDARY_TEXT_LIGHTNESS,
                a: 1
            };
        }
        const isLight = l > 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        const isBlue = !isNeutral && h > 205 && h < 245;
        let lx = isLight
            ? scale(l, 0.5, 1, DEFAULT_SECONDARY_TEXT_LIGHTNESS, pole1.l)
            : scale(l, 0, 0.5, pole1.l, DEFAULT_SECONDARY_TEXT_LIGHTNESS);
        if (isNeutral) {
            if (!hasSecondary) {
                return {h: pole1.h, s: pole1.s, l: lx, a};
            }
            const t = isLight ? (1 - l) * 2 : l * 2;
            const p = interpolatePoles(t, pole1, pole2);
            return {h: p.h, s: p.s, l: lx, a};
        }
        let hx = h;
        if (isBlue) {
            hx = modifyBlueFgHue(h);
            if (!isLight) {
                lx = scale(
                    l,
                    0,
                    0.5,
                    pole1.l,
                    Math.min(1, DEFAULT_SECONDARY_TEXT_LIGHTNESS + 0.05)
                );
            }
        }
        return {h: hx, s, l: lx, a};
    }

    function extendThemeCacheKeys(keys) {
        const extendedKeys = ["secondaryBackgroundColor", "secondaryTextColor"];
        extendedKeys.forEach((key) => {
            if (!keys.includes(key)) {
                keys.push(key);
            }
        });
    }

    const excludedSelectors = [
        "pre",
        "pre *",
        "code",
        '[aria-hidden="true"]',
        '[class*="fa-"]',
        ".fa",
        ".fab",
        ".fad",
        ".fal",
        ".far",
        ".fas",
        ".fass",
        ".fasr",
        ".fat",
        ".icofont",
        '[style*="font-"]',
        '[class*="icon"]',
        '[class*="Icon"]',
        '[class*="symbol"]',
        '[class*="Symbol"]',
        ".glyphicon",
        '[class*="material-symbol"]',
        '[class*="material-icon"]',
        "mu",
        '[class*="mu-"]',
        ".typcn",
        '[class*="vjs-"]'
    ];

    function createTextStyle(config) {
        const lines = [];
        lines.push(`*:not(${excludedSelectors.join(", ")}) {`);
        if (config.useFont && config.fontFamily) {
            lines.push(`  font-family: ${config.fontFamily} !important;`);
        }
        if (config.textStroke > 0) {
            lines.push(
                `  -webkit-text-stroke: ${config.textStroke}px !important;`
            );
            lines.push(`  text-stroke: ${config.textStroke}px !important;`);
        }
        lines.push("}");
        return lines.join("\n");
    }

    function createFilterMatrix(config) {
        let m = Matrix.identity();
        if (config.sepia !== 0) {
            m = multiplyMatrices(m, Matrix.sepia(config.sepia / 100));
        }
        if (config.grayscale !== 0) {
            m = multiplyMatrices(m, Matrix.grayscale(config.grayscale / 100));
        }
        if (config.contrast !== 100) {
            m = multiplyMatrices(m, Matrix.contrast(config.contrast / 100));
        }
        if (config.brightness !== 100) {
            m = multiplyMatrices(m, Matrix.brightness(config.brightness / 100));
        }
        if (config.mode === 1) {
            m = multiplyMatrices(m, Matrix.invertNHue());
        }
        return m;
    }

    function applyColorMatrix([r, g, b], matrix) {
        const rgb = [[r / 255], [g / 255], [b / 255], [1], [1]];
        const result = multiplyMatrices(matrix, rgb);
        return [0, 1, 2].map((i) =>
            clamp(Math.round(result[i][0] * 255), 0, 255)
        );
    }

    const Matrix = {
        identity() {
            return [
                [1, 0, 0, 0, 0],
                [0, 1, 0, 0, 0],
                [0, 0, 1, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        },
        invertNHue() {
            return [
                [0.333, -0.667, -0.667, 0, 1],
                [-0.667, 0.333, -0.667, 0, 1],
                [-0.667, -0.667, 0.333, 0, 1],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        },
        brightness(v) {
            return [
                [v, 0, 0, 0, 0],
                [0, v, 0, 0, 0],
                [0, 0, v, 0, 0],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        },
        contrast(v) {
            const t = (1 - v) / 2;
            return [
                [v, 0, 0, 0, t],
                [0, v, 0, 0, t],
                [0, 0, v, 0, t],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        },
        sepia(v) {
            return [
                [
                    0.393 + 0.607 * (1 - v),
                    0.769 - 0.769 * (1 - v),
                    0.189 - 0.189 * (1 - v),
                    0,
                    0
                ],
                [
                    0.349 - 0.349 * (1 - v),
                    0.686 + 0.314 * (1 - v),
                    0.168 - 0.168 * (1 - v),
                    0,
                    0
                ],
                [
                    0.272 - 0.272 * (1 - v),
                    0.534 - 0.534 * (1 - v),
                    0.131 + 0.869 * (1 - v),
                    0,
                    0
                ],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        },
        grayscale(v) {
            return [
                [
                    0.2126 + 0.7874 * (1 - v),
                    0.7152 - 0.7152 * (1 - v),
                    0.0722 - 0.0722 * (1 - v),
                    0,
                    0
                ],
                [
                    0.2126 - 0.2126 * (1 - v),
                    0.7152 + 0.2848 * (1 - v),
                    0.0722 - 0.0722 * (1 - v),
                    0,
                    0
                ],
                [
                    0.2126 - 0.2126 * (1 - v),
                    0.7152 - 0.7152 * (1 - v),
                    0.0722 + 0.9278 * (1 - v),
                    0,
                    0
                ],
                [0, 0, 0, 1, 0],
                [0, 0, 0, 0, 1]
            ];
        }
    }

    function throttle(callback) {
        let pending = false;
        let frameId = null;
        let lastArgs;
        const throttled = (...args) => {
            lastArgs = args;
            if (frameId) {
                pending = true;
            } else {
                callback(...lastArgs);
                frameId = requestAnimationFrame(() => {
                    frameId = null;
                    if (pending) {
                        callback(...lastArgs);
                        pending = false;
                    }
                });
            }
        };
        const cancel = () => {
            cancelAnimationFrame(frameId);
            pending = false;
            frameId = null;
        };
        return Object.assign(throttled, {cancel});
    }

    function createAsyncTasksQueue() {
        const tasks = [];
        let frameId = null;
        function runTasks() {
            let task;
            while ((task = tasks.shift())) {
                task();
            }
            frameId = null;
        }
        function add(task) {
            tasks.push(task);
            if (!frameId) {
                frameId = requestAnimationFrame(runTasks);
            }
        }
        function cancel() {
            tasks.splice(0);
            cancelAnimationFrame(frameId);
            frameId = null;
        }
        return {add, cancel};
    }

    function logInfo(...args) {}

    function logWarn(...args) {}

    function createNodeAsap({
        selectNode,
        createNode,
        updateNode,
        selectTarget,
        createTarget,
        isTargetMutation
    }) {
        const target = selectTarget();
        if (target) {
            const prev = selectNode();
            if (prev) {
                updateNode(prev);
            } else {
                createNode(target);
            }
        } else {
            const observer = new MutationObserver((mutations) => {
                const mutation = mutations.find(isTargetMutation);
                if (mutation) {
                    unsubscribe();
                    const target = selectTarget();
                    selectNode() || createNode(target);
                }
            });
            const ready = () => {
                if (document.readyState !== "complete") {
                    return;
                }
                unsubscribe();
                const target = selectTarget() || createTarget();
                selectNode() || createNode(target);
            };
            const unsubscribe = () => {
                document.removeEventListener("readystatechange", ready);
                observer.disconnect();
            };
            if (document.readyState === "complete") {
                ready();
            } else {
                document.addEventListener("readystatechange", ready);
                observer.observe(document, {childList: true, subtree: true});
            }
        }
    }

    function removeNode(node) {
        node && node.parentNode && node.parentNode.removeChild(node);
    }

    function iterateShadowHosts(root, iterator) {
        if (root == null) {
            return;
        }
        const walker = document.createTreeWalker(
            root,
            NodeFilter.SHOW_ELEMENT,
            {
                acceptNode(node) {
                    return node.shadowRoot == null
                        ? NodeFilter.FILTER_SKIP
                        : NodeFilter.FILTER_ACCEPT;
                }
            }
        );
        for (
            let node = root.shadowRoot ? walker.currentNode : walker.nextNode();
            node != null;
            node = walker.nextNode()
        ) {
            if (node.classList.contains("surfingkeys_hints_host")) {
                continue;
            }
            iterator(node);
            iterateShadowHosts(node.shadowRoot, iterator);
        }
    }

    let isDOMReady = () => {
        return (
            document.readyState === "complete" ||
            document.readyState === "interactive"
        );
    }

    function setIsDOMReady(newFunc) {
        isDOMReady = newFunc;
    }

    const readyStateListeners = new Set();

    function addDOMReadyListener(listener) {
        isDOMReady() ? listener() : readyStateListeners.add(listener);
    }

    function removeDOMReadyListener(listener) {
        readyStateListeners.delete(listener);
    }

    function isReadyStateComplete() {
        return document.readyState === "complete";
    }

    const HUGE_MUTATIONS_COUNT = 1000;

    function isHugeMutation(mutations) {
        if (mutations.length > HUGE_MUTATIONS_COUNT) {
            return true;
        }
        let addedNodesCount = 0;
        for (let i = 0; i < mutations.length; i++) {
            addedNodesCount += mutations[i].addedNodes.length;
            if (addedNodesCount > HUGE_MUTATIONS_COUNT) {
                return true;
            }
        }
        return false;
    }

    function getElementsTreeOperations(mutations) {
        const additions = new Set();
        const deletions = new Set();
        const moves = new Set();
        mutations.forEach((m) => {
            forEach(m.addedNodes, (n) => {
                if (n instanceof Element && n.isConnected) {
                    additions.add(n);
                }
            });
            forEach(m.removedNodes, (n) => {
                if (n instanceof Element) {
                    if (n.isConnected) {
                        moves.add(n);
                        additions.delete(n);
                    } else {
                        deletions.add(n);
                    }
                }
            });
        });
        const duplicateAdditions = [];
        const duplicateDeletions = [];
        additions.forEach((node) => {
            if (additions.has(node.parentElement)) {
                duplicateAdditions.push(node);
            }
        });
        deletions.forEach((node) => {
            if (deletions.has(node.parentElement)) {
                duplicateDeletions.push(node);
            }
        });
        duplicateAdditions.forEach((node) => additions.delete(node));
        duplicateDeletions.forEach((node) => deletions.delete(node));
        return {additions, moves, deletions};
    }

    const optimizedTreeObservers = new Map();

    const optimizedTreeCallbacks = new WeakMap();

    function createOptimizedTreeObserver(root, callbacks) {
        let observer;
        let observerCallbacks;
        let domReadyListener;
        if (optimizedTreeObservers.has(root)) {
            observer = optimizedTreeObservers.get(root);
            observerCallbacks = optimizedTreeCallbacks.get(observer);
        } else {
            let hadHugeMutationsBefore = false;
            let subscribedForReadyState = false;
            observer = new MutationObserver((mutations) => {
                if (isHugeMutation(mutations)) {
                    if (!hadHugeMutationsBefore || isDOMReady()) {
                        observerCallbacks.forEach(({onHugeMutations}) =>
                            onHugeMutations(root)
                        );
                    } else if (!subscribedForReadyState) {
                        domReadyListener = () =>
                            observerCallbacks.forEach(({onHugeMutations}) =>
                                onHugeMutations(root)
                            );
                        addDOMReadyListener(domReadyListener);
                        subscribedForReadyState = true;
                    }
                    hadHugeMutationsBefore = true;
                } else {
                    const elementsOperations =
                        getElementsTreeOperations(mutations);
                    observerCallbacks.forEach(({onMinorMutations}) =>
                        onMinorMutations(root, elementsOperations)
                    );
                }
            });
            observer.observe(root, {childList: true, subtree: true});
            optimizedTreeObservers.set(root, observer);
            observerCallbacks = new Set();
            optimizedTreeCallbacks.set(observer, observerCallbacks);
        }
        observerCallbacks.add(callbacks);
        return {
            disconnect() {
                observerCallbacks.delete(callbacks);
                if (domReadyListener) {
                    removeDOMReadyListener(domReadyListener);
                }
                if (observerCallbacks.size === 0) {
                    observer.disconnect();
                    optimizedTreeCallbacks.delete(observer);
                    optimizedTreeObservers.delete(root);
                }
            }
        };
    }

    function iterateCSSRules(
        rules,
        iterate,
        onImportError,
        importedSheets = new Set()
    ) {
        forEach(rules, (rule) => {
            if (isStyleRule(rule)) {
                iterate(rule);
                if (rule.cssRules?.length > 0) {
                    iterateCSSRules(
                        rule.cssRules,
                        iterate,
                        onImportError,
                        importedSheets
                    );
                }
            } else if (isImportRule(rule)) {
                try {
                    const importedSheet = rule.styleSheet;
                    if (!importedSheets.has(importedSheet)) {
                        importedSheets.add(importedSheet);
                        iterateCSSRules(
                            importedSheet.cssRules,
                            iterate,
                            onImportError,
                            importedSheets
                        );
                    }
                } catch (err) {
                    onImportError?.();
                }
            } else if (isMediaRule(rule)) {
                const media = Array.from(rule.media);
                const isScreenOrAllOrQuery = media.some(
                    (m) =>
                        m.startsWith("screen") ||
                        m.startsWith("all") ||
                        m.startsWith("(")
                );
                const isNotScreen =
                    !isScreenOrAllOrQuery &&
                    media.some((m) =>
                        ignoredMedia.some((i) => m.startsWith(i))
                    );
                if (isScreenOrAllOrQuery || !isNotScreen) {
                    iterateCSSRules(
                        rule.cssRules,
                        iterate,
                        onImportError,
                        importedSheets
                    );
                }
            } else if (isSupportsRule(rule)) {
                if (CSS.supports(rule.conditionText)) {
                    iterateCSSRules(
                        rule.cssRules,
                        iterate,
                        onImportError,
                        importedSheets
                    );
                }
            } else if (isLayerRule(rule)) {
                iterateCSSRules(
                    rule.cssRules,
                    iterate,
                    onImportError,
                    importedSheets
                );
            } else if (isContainerRule(rule)) {
                iterateCSSRules(
                    rule.cssRules,
                    iterate,
                    onImportError,
                    importedSheets
                );
            } else {
                logWarn(`CSSRule type not supported`, rule);
            }
        });
    }

    const ignoredMedia = [
        "aural",
        "braille",
        "embossed",
        "handheld",
        "print",
        "projection",
        "speech",
        "tty",
        "tv"
    ];

    const shorthandVarDependantProperties = [
        "background",
        "border",
        "border-color",
        "border-bottom",
        "border-left",
        "border-right",
        "border-top",
        "outline",
        "outline-color"
    ];

    function iterateCSSDeclarations(style, iterate) {
        const cssText = style.cssText;
        if (cssText.includes("var(")) {
            {
                shorthandVarDependantProperties.forEach((prop) => {
                    const val = style.getPropertyValue(prop);
                    if (val && val.includes("var(")) {
                        iterate(prop, val);
                    }
                });
            }
        }
        if (
            (cssText.includes("background-color: ;") ||
                cssText.includes("background-image: ;")) &&
            !style.getPropertyValue("background")
        ) {
            handleEmptyShorthand("background", style, iterate);
        }
        if (
            cssText.includes("border-") &&
            cssText.includes("-color: ;") &&
            !style.getPropertyValue("border")
        ) {
            handleEmptyShorthand("border", style, iterate);
        }
        forEach(style, (property) => {
            const value = style.getPropertyValue(property).trim();
            if (!value) {
                return;
            }
            iterate(property, value);
        });
    }

    function handleEmptyShorthand(shorthand, style, iterate) {
        const parentRule = style.parentRule;
        if (isStyleRule(parentRule)) {
            const sourceCSSText =
                parentRule.parentStyleSheet?.ownerNode?.textContent;
            if (sourceCSSText) {
                let escapedSelector = escapeRegExpSpecialChars(
                    parentRule.selectorText
                );
                escapedSelector = escapedSelector.replaceAll(/\s+/g, "\\s*");
                escapedSelector = escapedSelector.replaceAll(/::/g, "::?");
                const regexp = new RegExp(
                    `${escapedSelector}\\s*{[^}]*${shorthand}:\\s*([^;}]+)`
                );
                const match = sourceCSSText.match(regexp);
                if (match) {
                    iterate(shorthand, match[1]);
                }
            } else if (shorthand === "background") {
                iterate("background-color", "#ffffff");
                iterate("background-image", "none");
            }
        }
    }

    const cssURLRegex = /url\((('.*?')|(".*?")|([^\)]*?))\)/g;

    function getCSSURLValue(cssURL) {
        return cssURL
            .trim()
            .replace(/[\n\r\\]+/g, "")
            .replace(/^url\((.*)\)$/, "$1")
            .trim()
            .replace(/^"(.*)"$/, "$1")
            .replace(/^'(.*)'$/, "$1")
            .replace(/(?:\\(.))/g, "$1");
    }

    function getCSSBaseBath(url) {
        const cssURL = parseURL(url);
        return `${cssURL.origin}${cssURL.pathname.replace(/\?.*$/, "").replace(/(\/)([^\/]+)$/i, "$1")}`;
    }

    function replaceCSSRelativeURLsWithAbsolute($css, cssBasePath) {
        return $css.replace(cssURLRegex, (match) => {
            try {
                const url = getCSSURLValue(match);
                const absoluteURL = getAbsoluteURL(cssBasePath, url);
                const escapedURL = absoluteURL.replaceAll("'", "\\'");
                return `url('${escapedURL}')`;
            } catch (err) {
                logWarn(
                    "Not able to replace relative URL with Absolute URL, skipping"
                );
                return match;
            }
        });
    }

    const fontFaceRegex = /@font-face\s*{[^}]*}/g;

    function replaceCSSFontFace($css) {
        return $css.replace(fontFaceRegex, "");
    }

    const styleRules = new WeakSet();

    const importRules = new WeakSet();

    const mediaRules = new WeakSet();

    const supportsRules = new WeakSet();

    const layerRules = new WeakSet();

    const containerRules = new WeakSet();

    function isStyleRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return true;
        }
        if (rule.selectorText) {
            styleRules.add(rule);
            return true;
        }
        return false;
    }

    function isImportRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return false;
        }
        if (importRules.has(rule)) {
            return true;
        }
        if (rule.href) {
            importRules.add(rule);
            return true;
        }
        return false;
    }

    function isMediaRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return false;
        }
        if (mediaRules.has(rule)) {
            return true;
        }
        if (rule.media) {
            mediaRules.add(rule);
            return true;
        }
        return false;
    }

    function isSupportsRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return false;
        }
        if (supportsRules.has(rule)) {
            return true;
        }
        if (rule instanceof CSSSupportsRule) {
            supportsRules.add(rule);
            return true;
        }
        return false;
    }

    function isLayerRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return false;
        }
        if (layerRules.has(rule)) {
            return true;
        }
        if (isLayerRuleSupported && rule instanceof CSSLayerBlockRule) {
            layerRules.add(rule);
            return true;
        }
        return false;
    }

    function isContainerRule(rule) {
        if (!rule) {
            return false;
        }
        if (styleRules.has(rule)) {
            return false;
        }
        if (containerRules.has(rule)) {
            return true;
        }
        if (isContainerRuleSupported && rule instanceof CSSContainerRule) {
            containerRules.add(rule);
            return true;
        }
        return false;
    }

    function getRuleMediaText(rule) {
        const media = [];
        let parent = rule.parentRule;
        while (parent) {
            if (isMediaRule(parent)) {
                media.unshift(parent.media.mediaText);
            }
            parent = parent.parentRule;
        }
        return media.join(" and ");
    }

    let variablesSheet;

    const registeredColors = new Map();

    function getVariablesRule() {
        if (!variablesSheet) {
            return null;
        }
        const rules = variablesSheet.cssRules;
        for (let i = 0; i < rules.length; i++) {
            const rule = rules[i];
            if (rule.selectorText === ":root" && rule.style) {
                return rule;
            }
        }
        return null;
    }

    function registerVariablesSheet(sheet) {
        variablesSheet = sheet;
        const rule = getVariablesRule();
        if (!rule) {
            return;
        }
        const types = ["background", "text", "border"];
        registeredColors.forEach((registered) => {
            types.forEach((type) => {
                if (registered[type]) {
                    const {variable, value} = registered[type];
                    rule.style.setProperty(variable, value);
                }
            });
        });
    }

    function releaseVariablesSheet() {
        variablesSheet = null;
        clearColorPalette();
    }

    function getRegisteredVariableValue(type, registered) {
        return `var(${registered[type].variable}, ${registered[type].value})`;
    }

    function getRegisteredColor(type, parsed) {
        const hex = rgbToHexString(parsed);
        const registered = registeredColors.get(hex);
        if (registered?.[type]) {
            return getRegisteredVariableValue(type, registered);
        }
        return null;
    }

    function registerColor(type, parsed, value) {
        const hex = rgbToHexString(parsed);
        let registered;
        if (registeredColors.has(hex)) {
            registered = registeredColors.get(hex);
        } else {
            const parsed = parseColorWithCache(hex);
            registered = {parsed};
            registeredColors.set(hex, registered);
        }
        const variable = `--darkreader-${type}-${hex.replace("#", "")}`;
        registered[type] = {variable, value};
        getVariablesRule()?.style.setProperty(variable, value);
        return getRegisteredVariableValue(type, registered);
    }

    function getColorPalette() {
        const background = [];
        const border = [];
        const text = [];
        registeredColors.forEach((registered) => {
            if (registered.background) {
                background.push(registered.parsed);
            }
            if (registered.border) {
                border.push(registered.parsed);
            }
            if (registered.text) {
                text.push(registered.parsed);
            }
        });
        return {background, border, text};
    }

    function clearColorPalette() {
        registeredColors.clear();
    }

    function getBgPole(theme) {
        const isDarkScheme = theme.mode === 1;
        const prop = isDarkScheme
            ? "darkSchemeBackgroundColor"
            : "lightSchemeBackgroundColor";
        return theme[prop];
    }

    function getFgPole(theme) {
        const isDarkScheme = theme.mode === 1;
        const prop = isDarkScheme
            ? "darkSchemeTextColor"
            : "lightSchemeTextColor";
        return theme[prop];
    }

    const colorModificationCache = new Map();

    function clearColorModificationCache() {
        colorModificationCache.clear();
    }

    const rgbCacheKeys = ["r", "g", "b", "a"];

    const themeCacheKeys = [
        "mode",
        "brightness",
        "contrast",
        "grayscale",
        "sepia",
        "darkSchemeBackgroundColor",
        "darkSchemeTextColor",
        "lightSchemeBackgroundColor",
        "lightSchemeTextColor"
    ];

    function getCacheId(rgb, theme, poleA, poleB) {
        let resultId = "";
        rgbCacheKeys.forEach((key) => {
            resultId += `${rgb[key]};`;
        });
        themeCacheKeys.forEach((key) => {
            resultId += `${theme[key]};`;
        });
        resultId += `${poleA};${poleB}`;
        return resultId;
    }

    function modifyColorWithCache(
        rgb,
        theme,
        modifyHSL,
        poleColor,
        anotherPoleColor
    ) {
        let fnCache;
        if (colorModificationCache.has(modifyHSL)) {
            fnCache = colorModificationCache.get(modifyHSL);
        } else {
            fnCache = new Map();
            colorModificationCache.set(modifyHSL, fnCache);
        }
        const id = getCacheId(rgb, theme, poleColor, anotherPoleColor);
        if (fnCache.has(id)) {
            return fnCache.get(id);
        }
        const hsl = rgbToHSL(rgb);
        const pole = poleColor == null ? null : parseToHSLWithCache(poleColor);
        const anotherPole =
            anotherPoleColor == null
                ? null
                : parseToHSLWithCache(anotherPoleColor);
        const modified = modifyHSL(hsl, pole, anotherPole);
        const {r, g, b, a} = hslToRGB(modified);
        const matrix = createFilterMatrix({...theme, mode: 0});
        const [rf, gf, bf] = applyColorMatrix([r, g, b], matrix);
        const color =
            a === 1
                ? rgbToHexString({r: rf, g: gf, b: bf})
                : rgbToString({r: rf, g: gf, b: bf, a});
        fnCache.set(id, color);
        return color;
    }

    function modifyAndRegisterColor(type, rgb, theme, modifier) {
        const registered = getRegisteredColor(type, rgb);
        if (registered) {
            return registered;
        }
        const value = modifier(rgb, theme);
        return registerColor(type, rgb, value);
    }

    function modifyLightSchemeColor(rgb, theme) {
        const poleBg = getBgPole(theme);
        const poleFg = getFgPole(theme);
        return modifyColorWithCache(
            rgb,
            theme,
            modifyLightModeHSL,
            poleFg,
            poleBg
        );
    }

    function modifyLightModeHSL({h, s, l, a}, poleFg, poleBg) {
        const isDark = l < 0.5;
        let isNeutral;
        if (isDark) {
            isNeutral = l < 0.2 || s < 0.12;
        } else {
            const isBlue = h > 200 && h < 280;
            isNeutral = s < 0.24 || (l > 0.8 && isBlue);
        }
        let hx = h;
        let sx = s;
        if (isNeutral) {
            if (isDark) {
                hx = poleFg.h;
                sx = poleFg.s;
            } else {
                hx = poleBg.h;
                sx = poleBg.s;
            }
        }
        const lx = scale(l, 0, 1, poleFg.l, poleBg.l);
        return {h: hx, s: sx, l: lx, a};
    }

    function _modifyBackgroundColor(rgb, theme) {
        if (theme.mode === 0) {
            {
                const poles = getBackgroundPoles(theme);
                return modifyColorWithCache(
                    rgb,
                    theme,
                    modifyLightSchemeColorExtended,
                    poles[0],
                    poles[1]
                );
            }
        }
        {
            const poles = getBackgroundPoles(theme);
            return modifyColorWithCache(
                rgb,
                theme,
                modifyBgColorExtended,
                poles[0],
                poles[1]
            );
        }
    }

    function modifyBackgroundColor(
        rgb,
        theme,
        shouldRegisterColorVariable = true
    ) {
        if (!shouldRegisterColorVariable) {
            return _modifyBackgroundColor(rgb, theme);
        }
        return modifyAndRegisterColor(
            "background",
            rgb,
            theme,
            _modifyBackgroundColor
        );
    }

    function _modifyForegroundColor(rgb, theme) {
        if (theme.mode === 0) {
            {
                const poles = getTextPoles(theme);
                return modifyColorWithCache(
                    rgb,
                    theme,
                    modifyLightSchemeColorExtended,
                    poles[0],
                    poles[1]
                );
            }
        }
        {
            const poles = getTextPoles(theme);
            return modifyColorWithCache(
                rgb,
                theme,
                modifyFgColorExtended,
                poles[0],
                poles[1]
            );
        }
    }

    function modifyForegroundColor(
        rgb,
        theme,
        shouldRegisterColorVariable = true
    ) {
        if (!shouldRegisterColorVariable) {
            return _modifyForegroundColor(rgb, theme);
        }
        return modifyAndRegisterColor(
            "text",
            rgb,
            theme,
            _modifyForegroundColor
        );
    }

    function modifyBorderHSL({h, s, l, a}, poleFg, poleBg) {
        const isDark = l < 0.5;
        const isNeutral = l < 0.2 || s < 0.24;
        let hx = h;
        let sx = s;
        if (isNeutral) {
            if (isDark) {
                hx = poleFg.h;
                sx = poleFg.s;
            } else {
                hx = poleBg.h;
                sx = poleBg.s;
            }
        }
        const lx = scale(l, 0, 1, 0.5, 0.2);
        return {h: hx, s: sx, l: lx, a};
    }

    function _modifyBorderColor(rgb, theme) {
        if (theme.mode === 0) {
            return modifyLightSchemeColor(rgb, theme);
        }
        const poleFg = getFgPole(theme);
        const poleBg = getBgPole(theme);
        return modifyColorWithCache(
            rgb,
            theme,
            modifyBorderHSL,
            poleFg,
            poleBg
        );
    }

    function modifyBorderColor(rgb, theme, shouldRegisterColorVariable = true) {
        if (!shouldRegisterColorVariable) {
            return _modifyBorderColor(rgb, theme);
        }
        return modifyAndRegisterColor("border", rgb, theme, _modifyBorderColor);
    }

    function modifyShadowColor(rgb, theme) {
        return modifyBackgroundColor(rgb, theme);
    }

    function modifyGradientColor(rgb, theme) {
        return modifyBackgroundColor(rgb, theme);
    }

    const gradientLength = "gradient".length;

    const conicGradient = "conic-";

    const conicGradientLength = conicGradient.length;

    const radialGradient = "radial-";

    const linearGradient = "linear-";

    function parseGradient(value) {
        const result = [];
        let index = 0;
        let startIndex = conicGradient.length;
        while ((index = value.indexOf("gradient", startIndex)) !== -1) {
            let typeGradient;
            [linearGradient, radialGradient, conicGradient].find(
                (possibleType) => {
                    if (index - possibleType.length >= 0) {
                        const possibleGradient = value.substring(
                            index - possibleType.length,
                            index
                        );
                        if (possibleGradient === possibleType) {
                            if (
                                value.slice(
                                    index - possibleType.length - 10,
                                    index - possibleType.length - 1
                                ) === "repeating"
                            ) {
                                typeGradient = `repeating-${possibleType}gradient`;
                                return true;
                            }
                            if (
                                value.slice(
                                    index - possibleType.length - 8,
                                    index - possibleType.length - 1
                                ) === "-webkit"
                            ) {
                                typeGradient = `-webkit-${possibleType}gradient`;
                                return true;
                            }
                            typeGradient = `${possibleType}gradient`;
                            return true;
                        }
                    }
                }
            );
            if (!typeGradient) {
                break;
            }
            const {start, end} = getParenthesesRange(
                value,
                index + gradientLength
            );
            const match = value.substring(start + 1, end - 1);
            startIndex = end + 1 + conicGradientLength;
            result.push({
                typeGradient,
                match,
                offset: typeGradient.length + 2,
                index: index - typeGradient.length + gradientLength,
                hasComma: true
            });
        }
        if (result.length) {
            result[result.length - 1].hasComma = false;
        }
        return result;
    }

    const hostsBreakingOnStylePosition = [
        "chat.google.com",
        "gogoprivate.com",
        "gprivate.com",
        "www.berlingske.dk",
        "www.bloomberg.com",
        "www.diffusioneshop.com",
        "www.weekendavisen.dk",
        "zhale.me"
    ];

    const mode = hostsBreakingOnStylePosition.includes(location.hostname)
        ? "away"
        : "next";

  // ===== 预设（由宿主在注入时填入）=====
  var PRESET = window.__PR_DARK_PRESET;
  if (!PRESET || PRESET.enabled !== true) return;

  // mode 1 = 深色方案，0 = 浅色方案。
  // 由预设的底色明暗决定，用户不需要理解这个机制。
  var THEME = {
    mode: PRESET.mode == null ? 1 : PRESET.mode,
    brightness: PRESET.brightness == null ? 100 : PRESET.brightness,
    contrast: PRESET.contrast == null ? 100 : PRESET.contrast,
    grayscale: PRESET.grayscale == null ? 0 : PRESET.grayscale,
    sepia: PRESET.sepia == null ? 0 : PRESET.sepia,
    useFont: !!PRESET.forceFont,
    fontFamily: PRESET.forceFont || 'Segoe UI',
    textStroke: 0,
    // 必须是字符串 'dynamicTheme'，算法里按它分支
    engine: 'dynamicTheme',
    stylesheet: '',
    darkSchemeBackgroundColor:
      PRESET.background || 'rgb(24, 26, 27)',
    darkSchemeTextColor: PRESET.text || 'rgb(232, 230, 227)',
    lightSchemeBackgroundColor: 'rgb(255, 255, 255)',
    lightSchemeTextColor: 'rgb(24, 26, 27)',
    // 这两个不能省：极点（pole）计算会读它们，
    // 缺了就是 undefined，插值直接失败，表现为"文字色完全没变"。
    // 算法自身把空串当作"没有第二极点"。
    secondaryBackgroundColor: '',
    secondaryTextColor: '',
    scrollbarColor: '',
    selectionColor: 'auto',
    styleSystemControls: false,
    lightColorScheme: 'Default',
    darkColorScheme: 'Default',
    immediateModify: false,
  };

  var MAX_ELEMENTS = 6000;
  var BATCH_SIZE = 400;
  var processed = new WeakSet();
  var pending = [];
  var flushing = false;

  // ===== 跳过规则 =====
  //
  // 只跳过"算色会彻底毁掉内容"的元素：媒体、公式渲染器。
  //
  // 代码块（pre/code）**不跳过**。站点常给代码块设白色底，而父元素的
  // 文字色会被我们改成浅色 —— 白底浅字直接看不见。唯一稳妥的做法
  // 是让代码块一起算色：底色变深、文字变浅，语法高亮的彩色 span
  // 仍保留自己的色相（只是整体调亮）。
  // 代价是语法色值会变，这是"可读"与"原色"之间必须做的取舍。
  var SKIP_TAGS = {
    SCRIPT: 1, STYLE: 1, LINK: 1, META: 1, HEAD: 1, TITLE: 1,
    IMG: 1, VIDEO: 1, AUDIO: 1, CANVAS: 1, IFRAME: 1, OBJECT: 1, EMBED: 1,
    SVG: 1, MATH: 1,
  };

  var SKIP_SELECTORS = [
    '.katex', '.MathJax', 'mjx-container', '.arithmatex',
    '.mermaid', '.plantuml',
  ];
  var SKIP_SELECTOR_TEXT = SKIP_SELECTORS.join(',');

  function shouldSkip(el) {
    if (!el || el.nodeType !== 1) return true;
    var tag = el.tagName;
    if (SKIP_TAGS[tag]) return true;
    // 代码/公式容器：自身及后代都跳过
    var parent = el;
    var guard = 0;
    while (parent && parent.nodeType === 1 && guard++ < 8) {
      if (SKIP_TAGS[parent.tagName]) return true;
      if (parent.matches && parent.matches(SKIP_SELECTOR_TEXT)) return true;
      // role 或语义标记
      var role = parent.getAttribute && parent.getAttribute('role');
      if (role === 'code' || role === 'math') return true;
      parent = parent.parentElement;
    }
    return false;
  }

  // ===== 占位：第一帧就是深色 =====
  function applyPlaceholder() {
    var bg = THEME.darkSchemeBackgroundColor;
    var css =
      'html,body{background-color:' + bg + ' !important;' +
      'color-scheme:dark !important}';
    var style = document.createElement('style');
    style.id = '__pr_dark_placeholder';
    style.textContent = css;
    var host = document.head || document.documentElement;
    if (host) host.appendChild(style);
  }

  // ===== 元素算色 =====
  function toCss(color) {
    if (!color) return null;
    if (typeof color === 'string') return color;
    return rgbToString(color);
  }

  function processElement(el) {
    if (processed.has(el)) return;
    processed.add(el);
    if (shouldSkip(el)) return;

    var cs;
    try {
      cs = getComputedStyle(el);
    } catch (e) {
      return;
    }
    if (!cs) return;
    if (cs.display === 'none' || cs.visibility === 'hidden') return;

    // 每一段单独兜住：算法在个别颜色格式上失败，不能让整个遍历停掉。
    try {
      var bgColor = parseColorWithCache(cs.backgroundColor);
      if (bgColor && bgColor.a > 0.02) {
        var newBg = modifyBackgroundColor(bgColor, THEME);
        var bgCss = toCss(newBg);
        if (bgCss) el.style.setProperty('background-color', bgCss, 'important');
      }
    } catch (e) {
      note(errors, 'bg:' + (e && e.message));
    }

    try {
      var fgColor = parseColorWithCache(cs.color);
      if (fgColor && fgColor.a > 0.02) {
        var newFg = modifyForegroundColor(fgColor, THEME);
        var fgCss = toCss(newFg);
        if (fgCss) el.style.setProperty('color', fgCss, 'important');
      }
    } catch (e) {
      note(errors, 'fg:' + (e && e.message));
    }

    try {
      var bc = parseColorWithCache(cs.borderTopColor);
      if (bc && bc.a > 0.02 && parseFloat(cs.borderTopWidth) > 0) {
        var newBc = toCss(modifyBorderColor(bc, THEME));
        if (newBc) el.style.setProperty('border-color', newBc, 'important');
      }
    } catch (e) {
      note(errors, 'bd:' + (e && e.message));
    }
  }

  // 错误只记前若干条，避免刷爆内存
  var errors = [];
  function note(arr, msg) {
    if (arr.length < 5 && msg) arr.push(msg);
    window.__prDarkErrors = arr;
  }

  // ===== 代码块：只保可读性，不动配色 =====
  //
  // 代码高亮本身就是配色信息，改掉就毁了文档的表达。
  // 但我们的算色会给父元素设 `color`，代码块如果没有自己的 color
  // 就会继承过去 —— 白底浅字，直接看不见。
  //
  // 所以这里只做一件事：按代码块自己的底色，给容器一个能看清的默认文字色。
  // 背景一律不动，语法高亮 span 上的颜色也不会被覆盖。
  function fixCodeBlock(el) {
    var cs;
    try { cs = getComputedStyle(el); } catch (e) { return; }
    var bg = null;
    try { bg = parseColorWithCache(cs.backgroundColor); } catch (e) { return; }
    var dark;
    if (!bg || bg.a < 0.02) {
      // 透明：露出的是页面深色底，用浅字
      dark = false;
    } else {
      var l = 1;
      try { l = getSRGBLightness(rgbToHSL(bg)); } catch (e) { l = 1; }
      // 底色偏亮 → 需要深字
      dark = l > 0.5;
    }
    el.style.setProperty(
      'color',
      dark ? 'rgb(28, 30, 33)' : 'rgb(226, 228, 233)',
      'important'
    );
  }

  var CODE_TAGS = { PRE: 1, CODE: 1, KBD: 1, SAMP: 1 };

  // ===== 批量调度 =====
  function flush() {
    if (flushing) return;
    flushing = true;
    try {
      var count = 0;
      while (pending.length && count < BATCH_SIZE) {
        var el = pending.shift();
        processElement(el);
        count++;
      }
    } finally {
      // 必须无条件复位：否则任何一次异常都会让队列永久卡死，
      // 页面表现为"只有占位背景生效、一个字都没算色"。
      flushing = false;
    }
    if (pending.length) {
      requestAnimationFrame(flush);
    }
  }

  function enqueue(el) {
    if (!el || el.nodeType !== 1) return;
    if (processed.has(el)) return;
    if (pending.length > MAX_ELEMENTS) return;
    pending.push(el);
  }

  function walk(root) {
    if (!root) return;
    // 根节点本身也要处理：body.querySelectorAll('*') 只返回后代，
    // 不含 body —— 漏掉它会导致整页文字色停留在站点的原色（深底深字）。
    if (root.nodeType === 1) enqueue(root);
    var all;
    try {
      all = root.querySelectorAll('*');
    } catch (e) {
      return;
    }
    var n = Math.min(all.length, MAX_ELEMENTS);
    for (var i = 0; i < n; i++) enqueue(all[i]);
    flush();
  }

  // ===== 动态内容 =====
  function watch() {
    var mo = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === 'childList') {
          for (var j = 0; j < m.addedNodes.length; j++) {
            var node = m.addedNodes[j];
            if (node.nodeType !== 1) continue;
            enqueue(node);
            var kids = node.querySelectorAll ? node.querySelectorAll('*') : null;
            if (kids) {
              for (var k = 0; k < kids.length && k < 500; k++) enqueue(kids[k]);
            }
          }
        } else if (m.type === 'attributes') {
          // class/style 变化后重新算一次（先移除标记）
          processed.delete(m.target);
          enqueue(m.target);
        }
      }
      if (pending.length) requestAnimationFrame(flush);
    });
    mo.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style'],
    });
    return mo;
  }

  // ===== 启动 =====
  function start() {
    applyPlaceholder();
    if (THEME.useFont && THEME.fontFamily) {
      document.documentElement.style.setProperty(
        'font-family',
        '"' + THEME.fontFamily + '"',
        'important'
      );
    }
    document.documentElement.setAttribute('data-pr-dark', '1');
    walk(document.body || document.documentElement);
    watch();
    // 图片等异步加载完成后再补一轮
    addEventListener('load', function () {
      processed = new WeakSet();
      walk(document.body || document.documentElement);
    }, { once: true });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
    // DOM 还没解析完也要先顶住背景
    applyPlaceholder();
  } else {
    start();
  }
})();
