/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.apache.lucene.util.RamUsageEstimator;
import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.compute.data.DocVector;
import org.elasticsearch.compute.operator.BreakingBytesRefBuilder;
import org.elasticsearch.core.Nullable;
import org.elasticsearch.core.RefCounted;
import org.elasticsearch.core.Releasables;

import java.util.Arrays;
import java.util.Objects;

/**
 * Internal row to be used in the PriorityQueue instead of the full blown Page.
 * It mirrors somehow the Block build in the sense that it keeps around an array of offsets and a count of values (to account for
 * multivalues) to reference each position in each block of the Page.
 */
final class UngroupedRow implements Row {
    private static final long SHALLOW_SIZE = RamUsageEstimator.shallowSizeOfInstance(UngroupedRow.class);

    final CircuitBreaker breaker;

    /**
     * The sort keys, encoded into bytes so we can sort by calling {@link Arrays#compareUnsigned}.
     */
    private final BreakingBytesRefBuilder keys;

    @Override
    public BreakingBytesRefBuilder keys() {
        return keys;
    }

    /**
     * Values to reconstruct the row. Sort of. When we reconstruct the row we read
     * from both the {@link #keys} and the {@link #values}. So this only contains
     * what is required to reconstruct the row that isn't already stored in {@link #values}.
     */
    private final BreakingBytesRefBuilder values;

    @Override
    public BreakingBytesRefBuilder values() {
        return values;
    }

    /**
     * Reference counter for the shard this row belongs to, used for rows containing a {@link DocVector} to ensure that the shard
     * context before we build the final result.
     */
    @Nullable
    RefCounted shardRefCounter;

    UngroupedRow(CircuitBreaker breaker, int preAllocatedKeysSize, int preAllocatedValueSize) {
        breaker.addEstimateBytesAndMaybeBreak(SHALLOW_SIZE, "topn");
        this.breaker = breaker;
        boolean success = false;
        try {
            keys = new BreakingBytesRefBuilder(breaker, "topn", preAllocatedKeysSize);
            values = new BreakingBytesRefBuilder(breaker, "topn", preAllocatedValueSize);
            success = true;
        } finally {
            if (success == false) {
                close();
            }
        }
    }

    @Override
    public long ramBytesUsed() {
        return SHALLOW_SIZE + keys.ramBytesUsed() + values.ramBytesUsed();
    }

    @Override
    public void clear() {
        keys.clear();
        values.clear();
        clearRefCounters();
    }

    @Override
    public void close() {
        clearRefCounters();
        Releasables.closeExpectNoException(() -> breaker.addWithoutBreaking(-SHALLOW_SIZE), keys, values);
    }

    public void clearRefCounters() {
        if (shardRefCounter != null) {
            shardRefCounter.decRef();
        }
        shardRefCounter = null;
    }

    @Override
    public void setShardRefCounted(RefCounted shardRefCounted) {
        if (this.shardRefCounter != null) {
            this.shardRefCounter.decRef();
        }
        this.shardRefCounter = shardRefCounted;
        this.shardRefCounter.mustIncRef();
    }

    @Override
    public int compareTo(Row rhs) {
        if (rhs instanceof UngroupedRow other) {
            // TODO if we fill the trailing bytes with 0 we could do a comparison on the entire array
            // When Nik measured this it was marginally faster. But it's worth a bit of research.
            return -keys.bytesRefView().compareTo(other.keys.bytesRefView());
        } else {
            throw new IllegalArgumentException("rhs should be an UngroupedRow");
        }
    }

    @Override
    public boolean equals(Object o) {
        if (o == null || getClass() != o.getClass()) {
            return false;
        }

        UngroupedRow row = (UngroupedRow) o;
        return keys.bytesRefView().equals(row.keys.bytesRefView());
    }

    @Override
    public int hashCode() {
        return Objects.hashCode(keys);
    }

    @Override
    public String toString() {
        StringBuilder b = new StringBuilder("Row[key=");
        b.append(keys.bytesRefView());
        b.append(", values=");

        if (values.length() < 100) {
            b.append(values.bytesRefView());
        } else {
            b.append('[');
            assert values.bytesRefView().offset == 0;
            for (int i = 0; i < 100; i++) {
                if (i != 0) {
                    b.append(" ");
                }
                b.append(Integer.toHexString(values.bytesRefView().bytes[i] & 255));
            }
            b.append("...");
        }
        return b.append("]").toString();
    }
}
