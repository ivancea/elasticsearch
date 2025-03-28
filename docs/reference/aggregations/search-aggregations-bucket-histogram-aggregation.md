---
navigation_title: "Histogram"
mapped_pages:
  - https://www.elastic.co/guide/en/elasticsearch/reference/current/search-aggregations-bucket-histogram-aggregation.html
---

# Histogram aggregation [search-aggregations-bucket-histogram-aggregation]


A multi-bucket values source based aggregation that can be applied on numeric values or numeric range values extracted from the documents. It dynamically builds fixed size (a.k.a. interval) buckets over the values. For example, if the documents have a field that holds a price (numeric), we can configure this aggregation to dynamically build buckets with interval `5` (in case of price it may represent $5). When the aggregation executes, the price field of every document will be evaluated and will be rounded down to its closest bucket - for example, if the price is `32` and the bucket size is `5` then the rounding will yield `30` and thus the document will "fall" into the bucket that is associated with the key `30`. To make this more formal, here is the rounding function that is used:

```java
bucket_key = Math.floor((value - offset) / interval) * interval + offset
```

For range values, a document can fall into multiple buckets. The first bucket is computed from the lower bound of the range in the same way as a bucket for a single value is computed. The final bucket is computed in the same way from the upper bound of the range, and the range is counted in all buckets in between and including those two.

The `interval` must be a positive decimal, while the `offset` must be a decimal in `[0, interval)` (a decimal greater than or equal to `0` and less than `interval`)

The following snippet "buckets" the products based on their `price` by interval of `50`:

$$$histogram-aggregation-example$$$

```console
POST /sales/_search?size=0
{
  "aggs": {
    "prices": {
      "histogram": {
        "field": "price",
        "interval": 50
      }
    }
  }
}
```

And the following may be the response:

```console-result
{
  ...
  "aggregations": {
    "prices": {
      "buckets": [
        {
          "key": 0.0,
          "doc_count": 1
        },
        {
          "key": 50.0,
          "doc_count": 1
        },
        {
          "key": 100.0,
          "doc_count": 0
        },
        {
          "key": 150.0,
          "doc_count": 2
        },
        {
          "key": 200.0,
          "doc_count": 3
        }
      ]
    }
  }
}
```

## Minimum document count [_minimum_document_count]

The response above show that no documents has a price that falls within the range of `[100, 150)`. By default the response will fill gaps in the histogram with empty buckets. It is possible to change that and request buckets with a higher minimum count thanks to the `min_doc_count` setting:

$$$histogram-aggregation-min-doc-count-example$$$

```console
POST /sales/_search?size=0
{
  "aggs": {
    "prices": {
      "histogram": {
        "field": "price",
        "interval": 50,
        "min_doc_count": 1
      }
    }
  }
}
```

Response:

```console-result
{
  ...
  "aggregations": {
    "prices": {
      "buckets": [
        {
          "key": 0.0,
          "doc_count": 1
        },
        {
          "key": 50.0,
          "doc_count": 1
        },
        {
          "key": 150.0,
          "doc_count": 2
        },
        {
          "key": 200.0,
          "doc_count": 3
        }
      ]
    }
  }
}
```

$$$search-aggregations-bucket-histogram-aggregation-extended-bounds$$$
By default the `histogram` returns all the buckets within the range of the data itself, that is, the documents with the smallest values (on which with histogram) will determine the min bucket (the bucket with the smallest key) and the documents with the highest values will determine the max bucket (the bucket with the highest key). Often, when requesting empty buckets, this causes a confusion, specifically, when the data is also filtered.

To understand why, let’s look at an example:

Lets say the you’re filtering your request to get all docs with values between `0` and `500`, in addition you’d like to slice the data per price using a histogram with an interval of `50`. You also specify `"min_doc_count" : 0` as you’d like to get all buckets even the empty ones. If it happens that all products (documents) have prices higher than `100`, the first bucket you’ll get will be the one with `100` as its key. This is confusing, as many times, you’d also like to get those buckets between `0 - 100`.

With `extended_bounds` setting, you now can "force" the histogram aggregation to start building buckets on a specific `min` value and also keep on building buckets up to a `max` value (even if there are no documents anymore). Using `extended_bounds` only makes sense when `min_doc_count` is 0 (the empty buckets will never be returned if `min_doc_count` is greater than 0).

Note that (as the name suggest) `extended_bounds` is **not** filtering buckets. Meaning, if the `extended_bounds.min` is higher than the values extracted from the documents, the documents will still dictate what the first bucket will be (and the same goes for the `extended_bounds.max` and the last bucket). For filtering buckets, one should nest the histogram aggregation under a range `filter` aggregation with the appropriate `from`/`to` settings.

Example:

$$$histogram-aggregation-extended-bounds-example$$$

```console
POST /sales/_search?size=0
{
  "query": {
    "constant_score": { "filter": { "range": { "price": { "lte": "500" } } } }
  },
  "aggs": {
    "prices": {
      "histogram": {
        "field": "price",
        "interval": 50,
        "extended_bounds": {
          "min": 0,
          "max": 500
        }
      }
    }
  }
}
```

When aggregating ranges, buckets are based on the values of the returned documents. This means the response may include buckets outside of a query’s range. For example, if your query looks for values greater than 100, and you have a range covering 50 to 150, and an interval of 50, that document will land in 3 buckets - 50, 100, and 150. In general, it’s best to think of the query and aggregation steps as independent - the query selects a set of documents, and then the aggregation buckets those documents without regard to how they were selected. See [note on bucketing range fields](/reference/aggregations/search-aggregations-bucket-range-field-note.md) for more information and an example.

$$$search-aggregations-bucket-histogram-aggregation-hard-bounds$$$
The `hard_bounds` is a counterpart of `extended_bounds` and can limit the range of buckets in the histogram. It is particularly useful in the case of open [data ranges](/reference/elasticsearch/mapping-reference/range.md) that can result in a very large number of buckets.

Example:

$$$histogram-aggregation-hard-bounds-example$$$

```console
POST /sales/_search?size=0
{
  "query": {
    "constant_score": { "filter": { "range": { "price": { "lte": "500" } } } }
  },
  "aggs": {
    "prices": {
      "histogram": {
        "field": "price",
        "interval": 50,
        "hard_bounds": {
          "min": 100,
          "max": 200
        }
      }
    }
  }
}
```

In this example even though the range specified in the query is up to 500, the histogram will only have 2 buckets starting at 100 and 150. All other buckets will be omitted even if documents that should go to this buckets are present in the results.


## Order [_order_2]

By default the returned buckets are sorted by their `key` ascending, though the order behaviour can be controlled using the `order` setting. Supports the same `order` functionality as the [`Terms Aggregation`](/reference/aggregations/search-aggregations-bucket-terms-aggregation.md#search-aggregations-bucket-terms-aggregation-order).


## Offset [_offset]

By default the bucket keys start with 0 and then continue in even spaced steps of `interval`, e.g. if the interval is `10`, the first three buckets (assuming there is data inside them) will be `[0, 10)`, `[10, 20)`, `[20, 30)`. The bucket boundaries can be shifted by using the `offset` option.

This can be best illustrated with an example. If there are 10 documents with values ranging from 5 to 14, using interval `10` will result in two buckets with 5 documents each. If an additional offset `5` is used, there will be only one single bucket `[5, 15)` containing all the 10 documents.


## Response Format [_response_format]

By default, the buckets are returned as an ordered array. It is also possible to request the response as a hash instead keyed by the buckets keys:

$$$histogram-aggregation-keyed-example$$$

```console
POST /sales/_search?size=0
{
  "aggs": {
    "prices": {
      "histogram": {
        "field": "price",
        "interval": 50,
        "keyed": true
      }
    }
  }
}
```

Response:

```console-result
{
  ...
  "aggregations": {
    "prices": {
      "buckets": {
        "0.0": {
          "key": 0.0,
          "doc_count": 1
        },
        "50.0": {
          "key": 50.0,
          "doc_count": 1
        },
        "100.0": {
          "key": 100.0,
          "doc_count": 0
        },
        "150.0": {
          "key": 150.0,
          "doc_count": 2
        },
        "200.0": {
          "key": 200.0,
          "doc_count": 3
        }
      }
    }
  }
}
```


## Missing value [_missing_value_2]

The `missing` parameter defines how documents that are missing a value should be treated. By default they will be ignored but it is also possible to treat them as if they had a value.

$$$histogram-aggregation-missing-value-example$$$

```console
POST /sales/_search?size=0
{
  "aggs": {
    "quantity": {
      "histogram": {
        "field": "quantity",
        "interval": 10,
        "missing": 0 <1>
      }
    }
  }
}
```

1. Documents without a value in the `quantity` field will fall into the same bucket as documents that have the value `0`.



## Histogram fields [search-aggregations-bucket-histogram-aggregation-histogram-fields]

Running a histogram aggregation over histogram fields computes the total number of counts for each interval.

For example, executing a histogram aggregation against the following index that stores pre-aggregated histograms with latency metrics (in milliseconds) for different networks:

```console
PUT metrics_index
{
  "mappings": {
    "properties": {
      "network": {
        "properties": {
          "name": {
            "type": "keyword"
          }
        }
      },
      "latency_histo": {
         "type": "histogram"
      }
    }
  }
}

PUT metrics_index/_doc/1?refresh
{
  "network.name" : "net-1",
  "latency_histo" : {
      "values" : [1, 3, 8, 12, 15],
      "counts" : [3, 7, 23, 12, 6]
   }
}

PUT metrics_index/_doc/2?refresh
{
  "network.name" : "net-2",
  "latency_histo" : {
      "values" : [1, 6, 8, 12, 14],
      "counts" : [8, 17, 8, 7, 6]
   }
}

POST /metrics_index/_search?size=0
{
  "aggs": {
    "latency_buckets": {
      "histogram": {
        "field": "latency_histo",
        "interval": 5
      }
    }
  }
}
```

The `histogram` aggregation will sum the counts of each interval computed based on the `values` and return the following output:

```console-result
{
  ...
  "aggregations": {
    "latency_buckets": {
      "buckets": [
        {
          "key": 0.0,
          "doc_count": 18
        },
        {
          "key": 5.0,
          "doc_count": 48
        },
        {
          "key": 10.0,
          "doc_count": 25
        },
        {
          "key": 15.0,
          "doc_count": 6
        }
      ]
    }
  }
}
```

::::{important}
Histogram aggregation is a bucket aggregation, which partitions documents into buckets rather than calculating metrics over fields like metrics aggregations do. Each bucket represents a collection of documents which sub-aggregations can run on. On the other hand, a histogram field is a pre-aggregated field representing multiple values inside a single field: buckets of numerical data and a count of items/documents for each bucket. This mismatch between the histogram aggregations expected input (expecting raw documents) and the histogram field (that provides summary information) limits the outcome of the aggregation to only the doc counts for each bucket.

**Consequently, when executing a histogram aggregation over a histogram field, no sub-aggregations are allowed.**

::::


Also, when running histogram aggregation over histogram field the `missing` parameter is not supported.
