/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.compute.data.ElementType;
import org.elasticsearch.compute.data.Page;

import java.util.List;

final class UngroupedRowFiller implements RowFiller {
    private final ValueExtractor[] valueExtractors;
    private final KeyExtractor[] sortKeyExtractors;

    private int keyPreAllocSize = 0;
    private int valuePreAllocSize = 0;

    UngroupedRowFiller(
        List<ElementType> elementTypes,
        List<TopNEncoder> encoders,
        List<TopNOperator.SortOrder> sortOrders,
        boolean[] channelInKey,
        Page page
    ) {
        valueExtractors = new ValueExtractor[page.getBlockCount()];
        for (int b = 0; b < valueExtractors.length; b++) {
            valueExtractors[b] = ValueExtractor.extractorFor(
                elementTypes.get(b),
                encoders.get(b).toUnsortable(),
                channelInKey[b],
                page.getBlock(b)
            );
        }
        sortKeyExtractors = new KeyExtractor[sortOrders.size()];
        for (int k = 0; k < sortKeyExtractors.length; k++) {
            TopNOperator.SortOrder so = sortOrders.get(k);
            sortKeyExtractors[k] = KeyExtractor.extractorFor(
                elementTypes.get(so.channel()),
                encoders.get(so.channel()),
                so.asc(),
                so.nul(),
                so.nonNul(),
                page.getBlock(so.channel())
            );
        }
    }

    int preAllocatedKeysSize() {
        return keyPreAllocSize;
    }

    int preAlocatedValueSize() {
        return valuePreAllocSize;
    }

    @Override
    public void writeSortKey(int position, Row row) {
        for (KeyExtractor keyExtractor : sortKeyExtractors) {
            keyExtractor.writeKey(row.keys(), position);
        }
        keyPreAllocSize = RowFiller.newPreAllocSize(row.keys(), keyPreAllocSize);
    }

    @Override
    public void writeValues(int position, Row destination) {
        for (ValueExtractor e : valueExtractors) {
            var refCounted = e.getRefCountedForShard(position);
            if (refCounted != null) {
                destination.setShardRefCounted(refCounted);
            }
            e.writeValue(destination.values(), position);
        }
        valuePreAllocSize = RowFiller.newPreAllocSize(destination.values(), valuePreAllocSize);
    }
}
