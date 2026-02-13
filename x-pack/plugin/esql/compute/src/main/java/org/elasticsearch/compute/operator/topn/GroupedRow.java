/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.apache.lucene.util.RamUsageEstimator;
import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.compute.operator.BreakingBytesRefBuilder;
import org.elasticsearch.core.RefCounted;
import org.elasticsearch.core.Releasables;

final class GroupedRow implements Row {
    private static final long SHALLOW_SIZE = RamUsageEstimator.shallowSizeOfInstance(GroupedRow.class);
    private final UngroupedRow row;
    // TODO This isn't actually needed, since we already maintain this in the hash table's key. We will optimize it away when we get rid of
    // the hash table later on.
    private final BreakingBytesRefBuilder groupKey;

    GroupedRow(CircuitBreaker breaker, int preAllocatedKeysSize, int preAllocatedValueSize, int preAllocatedGroupKeySize) {
        breaker.addEstimateBytesAndMaybeBreak(SHALLOW_SIZE, "GroupedRow");
        UngroupedRow row = null;
        boolean success = false;
        try {
            row = new UngroupedRow(breaker, preAllocatedKeysSize, preAllocatedValueSize);
            this.row = row;
            this.groupKey = new BreakingBytesRefBuilder(breaker, "topn", preAllocatedGroupKeySize);
            success = true;
        } finally {
            if (success == false) {
                Releasables.closeExpectNoException(row);
                breaker.addWithoutBreaking(-SHALLOW_SIZE);
            }
        }
    }

    // TODO Nacho I don't like this
    @Override
    public int compareTo(Row rhs) {
        if (rhs instanceof GroupedRow other) {
            return this.row.compareTo(other.row);
        } else {
            throw new IllegalArgumentException("rhs should be an GroupedRow for the same groupKey");
        }
    }

    public BreakingBytesRefBuilder groupKey() {
        return groupKey;
    }

    @Override
    public BreakingBytesRefBuilder keys() {
        return row.keys();
    }

    @Override
    public void setShardRefCounted(RefCounted refCounted) {
        row.setShardRefCounted(refCounted);
    }

    @Override
    public BreakingBytesRefBuilder values() {
        return row.values();
    }

    @Override
    public void clear() {
        row.clear();
        groupKey.clear();
    }

    @Override
    public long ramBytesUsed() {
        return SHALLOW_SIZE + row.ramBytesUsed() + groupKey.ramBytesUsed();
    }

    @Override
    public void close() {
        Releasables.closeExpectNoException(() -> row.breaker.addWithoutBreaking(-SHALLOW_SIZE), row, groupKey);
    }
}
