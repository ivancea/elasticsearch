---
mapped_pages:
  - https://www.elastic.co/guide/en/elasticsearch/plugins/current/analysis-smartcn_stop.html
---

# smartcn_stop token filter [analysis-smartcn_stop]

The `smartcn_stop` token filter filters out stopwords defined by `smartcn` analyzer (`_smartcn_`), and any other custom stopwords specified by the user. This filter only supports the predefined `_smartcn_` stopwords list. If you want to use a different predefined list, then use the [`stop` token filter](/reference/text-analysis/analysis-stop-tokenfilter.md) instead.

```console
PUT smartcn_example
{
  "settings": {
    "index": {
      "analysis": {
        "analyzer": {
          "smartcn_with_stop": {
            "tokenizer": "smartcn_tokenizer",
            "filter": [
              "porter_stem",
              "my_smartcn_stop"
            ]
          }
        },
        "filter": {
          "my_smartcn_stop": {
            "type": "smartcn_stop",
            "stopwords": [
              "_smartcn_",
              "stack",
              "的"
            ]
          }
        }
      }
    }
  }
}

GET smartcn_example/_analyze
{
  "analyzer": "smartcn_with_stop",
  "text": "哈喽，我们是 Elastic   我们是 Elastic Stack（Elasticsearch、Kibana、Beats 和 Logstash）的开发公司。从股票行情到 Twitter 消息流，从 Apache 日志到 WordPress 博文，我们可以帮助人们体验搜索的强大力量，帮助他们以截然不同的方式探索和分析数据"
}
```

The above request returns:

```console-result
{
  "tokens": [
    {
      "token": "哈",
      "start_offset": 0,
      "end_offset": 1,
      "type": "word",
      "position": 0
    },
    {
      "token": "喽",
      "start_offset": 1,
      "end_offset": 2,
      "type": "word",
      "position": 1
    },
    {
      "token": "我们",
      "start_offset": 3,
      "end_offset": 5,
      "type": "word",
      "position": 3
    },
    {
      "token": "是",
      "start_offset": 5,
      "end_offset": 6,
      "type": "word",
      "position": 4
    },
    {
      "token": "elast",
      "start_offset": 7,
      "end_offset": 14,
      "type": "word",
      "position": 5
    },
    {
      "token": "我们",
      "start_offset": 17,
      "end_offset": 19,
      "type": "word",
      "position": 6
    },
    {
      "token": "是",
      "start_offset": 19,
      "end_offset": 20,
      "type": "word",
      "position": 7
    },
    {
      "token": "elast",
      "start_offset": 21,
      "end_offset": 28,
      "type": "word",
      "position": 8
    },
    {
      "token": "elasticsearch",
      "start_offset": 35,
      "end_offset": 48,
      "type": "word",
      "position": 11
    },
    {
      "token": "kibana",
      "start_offset": 49,
      "end_offset": 55,
      "type": "word",
      "position": 13
    },
    {
      "token": "beat",
      "start_offset": 56,
      "end_offset": 61,
      "type": "word",
      "position": 15
    },
    {
      "token": "和",
      "start_offset": 62,
      "end_offset": 63,
      "type": "word",
      "position": 16
    },
    {
      "token": "logstash",
      "start_offset": 64,
      "end_offset": 72,
      "type": "word",
      "position": 17
    },
    {
      "token": "开发",
      "start_offset": 74,
      "end_offset": 76,
      "type": "word",
      "position": 20
    },
    {
      "token": "公司",
      "start_offset": 76,
      "end_offset": 78,
      "type": "word",
      "position": 21
    },
    {
      "token": "从",
      "start_offset": 79,
      "end_offset": 80,
      "type": "word",
      "position": 23
    },
    {
      "token": "股票",
      "start_offset": 80,
      "end_offset": 82,
      "type": "word",
      "position": 24
    },
    {
      "token": "行情",
      "start_offset": 82,
      "end_offset": 84,
      "type": "word",
      "position": 25
    },
    {
      "token": "到",
      "start_offset": 84,
      "end_offset": 85,
      "type": "word",
      "position": 26
    },
    {
      "token": "twitter",
      "start_offset": 86,
      "end_offset": 93,
      "type": "word",
      "position": 27
    },
    {
      "token": "消息",
      "start_offset": 94,
      "end_offset": 96,
      "type": "word",
      "position": 28
    },
    {
      "token": "流",
      "start_offset": 96,
      "end_offset": 97,
      "type": "word",
      "position": 29
    },
    {
      "token": "从",
      "start_offset": 98,
      "end_offset": 99,
      "type": "word",
      "position": 31
    },
    {
      "token": "apach",
      "start_offset": 100,
      "end_offset": 106,
      "type": "word",
      "position": 32
    },
    {
      "token": "日志",
      "start_offset": 107,
      "end_offset": 109,
      "type": "word",
      "position": 33
    },
    {
      "token": "到",
      "start_offset": 109,
      "end_offset": 110,
      "type": "word",
      "position": 34
    },
    {
      "token": "wordpress",
      "start_offset": 111,
      "end_offset": 120,
      "type": "word",
      "position": 35
    },
    {
      "token": "博",
      "start_offset": 121,
      "end_offset": 122,
      "type": "word",
      "position": 36
    },
    {
      "token": "文",
      "start_offset": 122,
      "end_offset": 123,
      "type": "word",
      "position": 37
    },
    {
      "token": "我们",
      "start_offset": 124,
      "end_offset": 126,
      "type": "word",
      "position": 39
    },
    {
      "token": "可以",
      "start_offset": 126,
      "end_offset": 128,
      "type": "word",
      "position": 40
    },
    {
      "token": "帮助",
      "start_offset": 128,
      "end_offset": 130,
      "type": "word",
      "position": 41
    },
    {
      "token": "人们",
      "start_offset": 130,
      "end_offset": 132,
      "type": "word",
      "position": 42
    },
    {
      "token": "体验",
      "start_offset": 132,
      "end_offset": 134,
      "type": "word",
      "position": 43
    },
    {
      "token": "搜索",
      "start_offset": 134,
      "end_offset": 136,
      "type": "word",
      "position": 44
    },
    {
      "token": "强大",
      "start_offset": 137,
      "end_offset": 139,
      "type": "word",
      "position": 46
    },
    {
      "token": "力量",
      "start_offset": 139,
      "end_offset": 141,
      "type": "word",
      "position": 47
    },
    {
      "token": "帮助",
      "start_offset": 142,
      "end_offset": 144,
      "type": "word",
      "position": 49
    },
    {
      "token": "他们",
      "start_offset": 144,
      "end_offset": 146,
      "type": "word",
      "position": 50
    },
    {
      "token": "以",
      "start_offset": 146,
      "end_offset": 147,
      "type": "word",
      "position": 51
    },
    {
      "token": "截然不同",
      "start_offset": 147,
      "end_offset": 151,
      "type": "word",
      "position": 52
    },
    {
      "token": "方式",
      "start_offset": 152,
      "end_offset": 154,
      "type": "word",
      "position": 54
    },
    {
      "token": "探索",
      "start_offset": 154,
      "end_offset": 156,
      "type": "word",
      "position": 55
    },
    {
      "token": "和",
      "start_offset": 156,
      "end_offset": 157,
      "type": "word",
      "position": 56
    },
    {
      "token": "分析",
      "start_offset": 157,
      "end_offset": 159,
      "type": "word",
      "position": 57
    },
    {
      "token": "数据",
      "start_offset": 159,
      "end_offset": 161,
      "type": "word",
      "position": 58
    }
  ]
}
```

