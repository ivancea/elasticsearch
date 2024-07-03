/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

import org.elasticsearch.common.util.BitArray;
import org.elasticsearch.core.Releasables;

/**
 * Builder for {@link BooleanVector}s that grows as needed.
 * This class is generated. Do not edit it.
 */
final class BooleanVectorBuilder extends AbstractVectorBuilder implements BooleanVector.Builder {

    private BitArray values;

    BooleanVectorBuilder(int estimatedSize, BlockFactory blockFactory) {
        super(blockFactory);
        int initialSize = Math.max(estimatedSize, 2);
        adjustBreaker(initialSize);
        values = new BitArray(initialSize, blockFactory.bigArrays());
    }

    @Override
    public BooleanVectorBuilder appendBoolean(boolean value) {
        ensureCapacity();
        if (value) {
            values.set(valueCount);
        }
        valueCount++;
        return this;
    }

    @Override
    protected int elementSize() {
        return Byte.BYTES;
    }

    @Override
    protected int valuesLength() {
        return Integer.MAX_VALUE; // allow the BitArray through its own append
    }

    @Override
    protected void growValuesArray(int newSize) {
        throw new AssertionError("should not reach here");
    }

    @Override
    public BooleanVector build() {
        finish();
        BooleanVector vector;
        if (valueCount == 1) {
            vector = blockFactory.newConstantBooleanBlockWith(values.get(0), 1, estimatedBytes).asVector();

            Releasables.closeExpectNoException(values);
        } else {
            vector = blockFactory.newBooleanArrayVector(values, valueCount, estimatedBytes);
        }
        built();
        return vector;
    }

    @Override
    public void extraClose() {
        Releasables.closeExpectNoException(values);
    }
}
