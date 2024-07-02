/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

import org.elasticsearch.common.util.BitArray;

/**
 * Builder for {@link BooleanVector}s that never grows. Prefer this to
 * {@link BooleanVectorBuilder} if you know the precise size up front because
 * it's faster.
 * This class is generated. Do not edit it.
 */
final class BooleanVectorFixedBuilder implements BooleanVector.FixedBuilder {
    private final BlockFactory blockFactory;
    private BitArray values;
    private int size;
    private final long preAdjustedBytes;
    /**
     * The next value to write into. {@code -1} means the vector has already
     * been built.
     */
    private int nextIndex;

    private boolean closed;

    BooleanVectorFixedBuilder(int size, BlockFactory blockFactory) {
        this.blockFactory = blockFactory;
        this.values = new BitArray(size, blockFactory.bigArrays());
        this.size = size;
        preAdjustedBytes = ramBytesUsed(size, this.values);
        blockFactory.adjustBreaker(preAdjustedBytes);
    }

    @Override
    public BooleanVectorFixedBuilder appendBoolean(boolean value) {
        if (value) {
            values.set(nextIndex);
        }
        nextIndex++;
        return this;
    }

    @Override
    public BooleanVectorFixedBuilder appendBoolean(int idx, boolean value) {
        if (value) {
            values.set(idx);
        } else {
            values.clear(idx);
        }
        return this;
    }

    private static long ramBytesUsed(int size, BitArray values) {
        return size == 1 ? ConstantBooleanVector.RAM_BYTES_USED : BooleanArrayVector.ramBytesEstimated(values);
    }

    @Override
    public long estimatedBytes() {
        return ramBytesUsed(size, values);
    }

    @Override
    public BooleanVector build() {
        if (closed) {
            throw new IllegalStateException("already closed");
        }
        closed = true;
        BooleanVector vector;
        if (size == 1) {
            vector = blockFactory.newConstantBooleanBlockWith(values.get(0), 1, preAdjustedBytes).asVector();
        } else {
            vector = blockFactory.newBooleanArrayVector(values, size, preAdjustedBytes);
        }
        assert vector.ramBytesUsed() == preAdjustedBytes : "fixed Builders should estimate the exact ram bytes used";
        return vector;
    }

    @Override
    public void close() {
        if (closed == false) {
            // If nextIndex < 0 we've already built the vector
            closed = true;
            blockFactory.adjustBreaker(-preAdjustedBytes);
        }
    }

    boolean isReleased() {
        return closed;
    }
}
