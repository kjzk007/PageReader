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

    let canvas$1;

    let context$1;

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

    let observer$1;

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

    function logWarn(...args) {}

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

    const readyStateListeners = new Set();

    function addDOMReadyListener(listener) {
        isDOMReady() ? listener() : readyStateListeners.add(listener);
    }

    function removeDOMReadyListener(listener) {
        readyStateListeners.delete(listener);
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

    const fontFaceRegex = /@font-face\s*{[^}]*}/g;

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

    const gradientLength = "gradient".length;

    const conicGradient = "conic-";

    const conicGradientLength = conicGradient.length;

    const radialGradient = "radial-";

    const linearGradient = "linear-";

    const resolvers$1 = new Map();

    let addFilterSelector$1 = null;

    let canUseSheetProxy$1 = false;

    const overrides$1 = new WeakSet();

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

    let prevTheme$1 = null;

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
    // 极点（pole）计算要读这两个。
    //
    // 不能用空串：算法会把 "" 传进 parseColorWithCache，解析失败后
    // 插值出来的是一个无意义的高饱和色 —— 实测整个 body 背景变成
    // rgb(0,255,255) 青色。给它们一对「次要背景/次要文字」的实色即可，
    // 语义上正好对应站点里的卡片、侧栏这类次级区域。
      secondaryBackgroundColor:
        PRESET.secondaryBackground || PRESET.background || 'rgb(24, 26, 27)',
      secondaryTextColor:
        PRESET.secondaryText || PRESET.text || 'rgb(232, 230, 227)',
    scrollbarColor: '',
    selectionColor: 'auto',
    styleSystemControls: false,
    lightColorScheme: 'Default',
    darkColorScheme: 'Default',
    immediateModify: false,
  };

  // 错误记录必须在这里初始化 —— 放在 note() 附近的话，第一次异常
  // 发生在赋值之前，note 内部 arr.length 会再抛一次，把原始错误吞掉。
  var errors = [];
  window.__prDarkErrors = errors;

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
    // 代码块不参与算色 —— 文字和语法高亮必须保持站点原样。
    //
    // 语法高亮本身就是配色信息，逐元素改色会把关键字的红、字符串的
    // 绿全洗掉。但**背景**要跟随主题（见 applyUserOverrides 里的规则）：
    // 站点普遍给代码块设白底，留一块白在深色页面上很刺眼。
    PRE: 1, CODE: 1, KBD: 1, SAMP: 1,
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
  /// 把用户指定的链接色、选中色、图片亮度写成一张全局样式表。
  ///
  /// 这三项和逐元素算色是两条独立通路：
  ///   - 链接色是「用户明确指定」，优先于算色结果；
  ///   - 选中色只能靠 ::selection 伪元素，算色碰不到；
  ///   - 图片亮度必须用 filter，逐元素改背景没有意义。
  function applyUserOverrides() {
    var rules = [];

    // 链接：只覆盖正文里的链接，放过按钮、导航和卡片，
    // 否则站点精心设计的按钮会一片死蓝。
    var link = PRESET.link;
    if (link) {
      rules.push(
        'a[href]:not([class*="btn"]):not([class*="button"])' +
          ':not([role="button"])' +
          '{color:' + link + ' !important}'
      );
    }

    // 选中文本
    var sel = PRESET.selection;
    if (sel) {
      rules.push('::selection{background-color:' + sel + ' !important}');
      rules.push('::-moz-selection{background-color:' + sel + ' !important}');
    }


    // 代码块：只换背景，文字和语法高亮保持站点原样。
    //
    // 高亮是文档的配色信息（关键字红、字符串绿），逐元素算色会洗掉它；
    // 但背景必须跟随主题 —— 站点给代码块设的白底放在深色页面上很刺眼。
    var codeBg = PRESET.codeBackground;
    if (codeBg) {
      rules.push(
        'pre,code,kbd,samp{background-color:' + codeBg + ' !important}'
      );
    }

    // 图片亮度：深底上原图刺眼，这里统一压暗。
    var ib = PRESET.imageBrightness;
    if (typeof ib === 'number' && ib !== 100) {
      var pct = Math.max(0, ib) + '%';
      rules.push('img,video,picture img{filter:brightness(' + pct + ') !important}');
    }

    if (!rules.length) return;
    var style = document.createElement('style');
    style.id = '__pr_user_overrides';
    style.textContent = rules.join('\n');
    var host = document.head || document.documentElement;
    if (host) host.appendChild(style);
  }

  function applyPlaceholder() {
    var bg = THEME.darkSchemeBackgroundColor;
    var css =
      'html,body{background-color:' + bg + ' !important;' +
      'color-scheme:' + (THEME.mode === 1 ? 'dark' : 'light') + ' !important}';
    var style = document.createElement('style');
    style.id = '__pr_dark_placeholder';
    style.textContent = css;
    var host = document.head || document.documentElement;
    if (host) host.appendChild(style);
  }

  // ===== 元素算色 =====
  /// 按用户设定的亮度/对比度调整**文字色**。
  ///
  /// 只作用文字，不作用背景 —— 背景亮度一旦跟着放大，大面积容器
  /// （main/article 的浅色底）会成片撞到 255，整个页面发白，
  /// 看起来像"渲染坏了"。用户要的也只是"文字亮一点"。
  ///
  /// ── 为什么必须在算色之后做 ──
  ///
  /// 引擎的颜色修改算法里根本没有 brightness / contrast 这两个参数
  /// （它们只在 filter 模式下被 createFilterMatrix 用到），所以这两个
  /// 滑块以前是死参数。
  ///
  /// 但调整必须放在算色**之后**：算法的极点映射假设输入是站点原本的
  /// 浅色配色，先把它压成中灰再喂进去，会被映射成更暗的颜色 ——
  /// 实测 h1 从可读的浅灰变成 rgb(29,29,32)，在深底上直接消失。
  function adjustTextColor(color) {
    var b = THEME.brightness;
    var c = THEME.contrast;
    if (b === 100 && c === 100) return color;

    // 算色函数返回的可能是 rgb 字符串而不是 {r,g,b,a} ——
    // 直接按对象取值会得到 undefined，算出 NaN，写进 style 时
    // 浏览器当成无效值整个丢掉，表现为"算色完全不生效"。
    var rgb = color;
    if (typeof color === 'string') {
      rgb = parseColorWithCache(color);
    }
    if (!rgb || typeof rgb.r !== 'number') return color;

    var r = rgb.r, g = rgb.g, bl = rgb.b;

    // 亮度：向白/向黑插值，而不是按倍数乘。
    //
    // 倍数乘会把接近白的中亮文字直接顶到 255 —— 实测亮度调到 112
    // 之后，整页文字全变纯白，层次全丢，看起来像"渲染坏了"。
    // 插值最多只吃掉 30% 的余量，调大调小都还留得住层次。
    if (b !== 100) {
      var t = (b - 100) / 100; // 负数=压暗，正数=提亮
      var k = Math.min(Math.abs(t), 0.6) * 0.5;
      if (t > 0) {
        r = r + (255 - r) * k;
        g = g + (255 - g) * k;
        bl = bl + (255 - bl) * k;
      } else {
        r = r * (1 - k);
        g = g * (1 - k);
        bl = bl * (1 - k);
      }
    }

    // 对比度：缩放「文字与页面底色」的差值，而不是围绕中灰 128 拉伸。
    //
    // 中灰轴心的做法在深色主题下几乎看不出效果 —— 文字本身已经接近
    // 中亮（rgb(153,158,169)），绕 128 拉伸只挪动十几个色阶。
    // 改成以底色为基准放大/缩小差值，效果直接对得上"文字和背景的
    // 反差"，160 时文字明显更亮，20 时明显更暗。
    if (c !== 100) {
      var base = null;
      try {
        base = parseColorWithCache(THEME.darkSchemeBackgroundColor);
      } catch (e) {}
      if (!base || typeof base.r !== 'number') {
        base = { r: 0, g: 0, b: 0 };
      }
      var ct = (c - 100) / 100;
      var cf = 1 + Math.max(-0.85, Math.min(1.2, ct));
      r = base.r + (r - base.r) * cf;
      g = base.g + (g - base.g) * cf;
      bl = base.b + (bl - base.b) * cf;
    }

    return {
      r: Math.max(0, Math.min(255, r)),
      g: Math.max(0, Math.min(255, g)),
      b: Math.max(0, Math.min(255, bl)),
      a: rgb.a,
    };
  }

  /// 是不是需要套用用户链接色的元素。
  ///
  /// 只排除真正的按钮（class 含 btn/button、role=button），其余链接一律上色。
  /// 不要用「有没有背景色」来判断 —— 实测导航栏链接普遍带底色，
  /// 拿这个当排除条件会把整页链接都放过，用户改了半天没反应。
  function isUserLink(el) {
    if (!PRESET.link) return false;
    if (el.tagName !== 'A') return false;
    if (!el.hasAttribute('href')) return false;
    var cls = (el.className && typeof el.className === 'string')
      ? el.className.toLowerCase()
      : '';
    if (cls.indexOf('btn') >= 0 || cls.indexOf('button') >= 0) return false;
    if (el.getAttribute('role') === 'button') return false;
    return true;
  }

  function toCss(color) {
    if (!color) return null;
    if (typeof color === 'string') return color;
    return rgbToString(color);
  }

  function processElement(el) {
    if (processed.has(el)) return;
    processed.add(el);
    try {
      processElementInner(el);
    } catch (e) {
      note(errors, 'outer:' + (e && e.message));
    }
  }

  function processElementInner(el) {
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
    //
    // ── html / body 的背景必须跳过 ──
    //
    // 占位样式已经给 html,body 设了主题底色（!important）。如果这里
    // 再按"站点的浅色背景"算一遍，读到的 cs.backgroundColor 其实是
    // 占位刷上去的那层颜色 —— 等于把用户选的底色又当输入算一次，
    // 蓝色会被映射成黑色，页面变成"外面蓝、里面黑"。
    // 这一层的背景完全交给占位，这里只处理它们的文字色。
    var isRootContainer =
      el === document.documentElement || el === document.body;
    try {
      if (!isRootContainer) {
        var bgColor = parseColorWithCache(cs.backgroundColor);
        if (bgColor && bgColor.a > 0.02) {
          var newBg = modifyBackgroundColor(bgColor, THEME);
          var bgCss = toCss(newBg);
          if (bgCss) el.style.setProperty('background-color', bgCss, 'important');
        }
      }
    } catch (e) {
      note(errors, 'bg:' + (e && e.message));
    }

    try {
      // 链接色优先于算色结果。
      //
      // 不能只靠注入一张样式表：算色会给每个元素写内联 style，
      // 而内联的 !important 优先级高于样式表的 !important ——
      // 结果就是链接色被默默盖掉，用户在设置里改半天没反应。
      if (isUserLink(el)) {
        el.style.setProperty('color', PRESET.link, 'important');
      } else {
        var rawFg = parseColorWithCache(cs.color);
        if (rawFg && rawFg.a > 0.02) {
          var newFg = adjustTextColor(modifyForegroundColor(rawFg, THEME));
          var fgCss = toCss(newFg);
          if (fgCss) el.style.setProperty('color', fgCss, 'important');
        }
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
  function note(arr, msg) {
    try {
      if (arr && arr.length < 8 && msg) arr.push(msg);
    } catch (e) {}
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
    applyUserOverrides();
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
