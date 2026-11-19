import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/chapter_extractor.dart';

void main() {
  group('中文章节号', () {
    test('第 12 章', () {
      expect(ChapterExtractor.extract('第 12 章 并发编程'), '第 12 章');
    });

    test('第12章 无空格', () {
      expect(ChapterExtractor.extract('第12章 并发编程'), '第 12 章');
    });

    test('第十二章 转阿拉伯数字', () {
      expect(ChapterExtractor.extract('第十二章 生命周期'), '第 12 章');
    });

    test('第三章', () {
      expect(ChapterExtractor.extract('第三章 所有权'), '第 3 章');
    });

    test('第二十章', () {
      expect(ChapterExtractor.extract('第二十章 收尾'), '第 20 章');
    });
  });

  group('英文章节号', () {
    test('Chapter 3', () {
      expect(ChapterExtractor.extract('Chapter 3: Common Concepts'), 'Chapter 3');
    });

    test('CHAPTER 12 大写', () {
      expect(ChapterExtractor.extract('CHAPTER 12 Traits'), 'Chapter 12');
    });

    test('Ch. 5', () {
      expect(ChapterExtractor.extract('Ch. 5 Ownership'), 'Ch. 5');
    });
  });

  group('数字编号', () {
    test('开头 3.2', () {
      expect(ChapterExtractor.extract('3.2 生命周期'), '3.2');
    });

    test('多层 2.4.1', () {
      expect(ChapterExtractor.extract('2.4.1 Advanced'), '2.4.1');
    });

    test('单数字开头带标题', () {
      expect(ChapterExtractor.extract('4 Getting Started'), '第 4 章');
    });

    test('年份不误判', () {
      // "2024" 是四位,不在单/双数字规则里,应提取不到
      expect(ChapterExtractor.extract('2024 Release Notes'), isNull);
    });
  });

  group('提取不到', () {
    test('普通标题返回 null', () {
      expect(ChapterExtractor.extract('Defining Shared Behavior with Traits'), isNull);
      expect(ChapterExtractor.extract('The Rust Programming Language'), isNull);
      expect(ChapterExtractor.extract('首页'), isNull);
    });

    test('空标题返回 null', () {
      expect(ChapterExtractor.extract(''), isNull);
      expect(ChapterExtractor.extract('   '), isNull);
    });
  });
}
