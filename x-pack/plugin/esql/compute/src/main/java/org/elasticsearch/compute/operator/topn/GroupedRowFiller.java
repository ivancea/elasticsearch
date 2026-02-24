/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.compute.data.ElementType;
import org.elasticsearch.compute.data.IntBlock;
import org.elasticsearch.compute.data.Page;
import org.elasticsearch.core.Releasables;

import java.util.List;

/**
 * A {@link RowFiller} for grouped top-N that delegates sort-key and value writing to an
 * {@link UngroupedRowFiller} and sets the pre-computed group ID (from a {@link
 * org.elasticsearch.compute.aggregation.blockhash.BlockHash}) on each {@link GroupedRow}.
 * <p>
 * When group keys are multivalued, a single page position may map to multiple group IDs
 * (one per combination of multivalue key values). The {@link #groupIdCount} and
 * {@link #setGroupId} methods allow the caller to iterate over all groups for a position.
 */
final class GroupedRowFiller implements RowFiller {
    private final UngroupedRowFiller ungroupedRowFiller;
    private final IntBlock groupIds;

    private int keyPreAllocSize = 0;
    private int valuePreAllocSize = 0;

    GroupedRowFiller(
        List<ElementType> elementTypes,
        List<TopNEncoder> encoders,
        List<TopNOperator.SortOrder> sortOrders,
        boolean[] channelInKey,
        IntBlock groupIds,
        Page page
    ) {
        this.ungroupedRowFiller = new UngroupedRowFiller(elementTypes, encoders, sortOrders, channelInKey, page);
        this.groupIds = groupIds;
    }

    int preAllocatedValueSize() {
        return valuePreAllocSize;
    }

    int preAllocatedKeysSize() {
        return keyPreAllocSize;
    }

    @Override
    public void writeSortKey(int i, Row row) {
        ungroupedRowFiller.writeSortKey(i, row);
        ((GroupedRow) row).groupId = groupIds.getInt(groupIds.getFirstValueIndex(i));
        keyPreAllocSize = RowFiller.newPreAllocSize(row.keys(), keyPreAllocSize);
    }

    @Override
    public void writeValues(int i, Row row) {
        ungroupedRowFiller.writeValues(i, row);
        valuePreAllocSize = RowFiller.newPreAllocSize(row.values(), valuePreAllocSize);
    }

    @Override
    public int groupIdCount(int i) {
        return groupIds.getValueCount(i);
    }

    @Override
    public void setGroupId(int i, int groupIndex, Row row) {
        ((GroupedRow) row).groupId = groupIds.getInt(groupIds.getFirstValueIndex(i) + groupIndex);
    }

    @Override
    public void close() {
        Releasables.closeExpectNoException(groupIds);
    }
}
