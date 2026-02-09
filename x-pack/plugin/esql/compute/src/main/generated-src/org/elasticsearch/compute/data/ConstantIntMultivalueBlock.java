/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

// begin generated imports
import org.apache.lucene.util.RamUsageEstimator;
import org.elasticsearch.common.unit.ByteSizeValue;
import org.elasticsearch.core.ReleasableIterator;
import org.elasticsearch.core.Releasables;
// end generated imports

/**
 * A Block that stores a constant multivalue for all positions.
 * Each position has the same set of values, avoiding the need to duplicate values.
 * This class is generated. Edit {@code X-ConstantMultivalueBlock.java.st} instead.
 */
public final class ConstantIntMultivalueBlock extends AbstractNonThreadSafeRefCounted implements IntBlock {

    private static final long BASE_RAM_BYTES_USED = RamUsageEstimator.shallowSizeOfInstance(ConstantIntMultivalueBlock.class);

    private final IntVector values;
    private final int positionCount;

    /**
     * Creates a constant multivalue block.
     * @param values the vector containing the multivalue (owned by this block)
     * @param positionCount the number of positions in this block
     */
    ConstantIntMultivalueBlock(IntVector values, int positionCount) {
        assert values.getPositionCount() > 0 : "multivalue must have at least one value";
        this.values = values;
        this.positionCount = positionCount;
    }

    @Override
    public IntVector asVector() {
        // Cannot return a vector because this block has multivalues
        return null;
    }

    @Override
    public int getInt(int valueIndex) {
        return values.getInt(valueIndex);
    }

    @Override
    public int getPositionCount() {
        return positionCount;
    }

    @Override
    public int getFirstValueIndex(int position) {
        // All positions start at the same index (0) since we share the same values
        return 0;
    }

    @Override
    public int getValueCount(int position) {
        return values.getPositionCount();
    }

    @Override
    public int getTotalValueCount() {
        return values.getPositionCount() * positionCount;
    }

    @Override
    public ElementType elementType() {
        return ElementType.INT;
    }

    @Override
    public boolean isNull(int position) {
        return false;
    }

    @Override
    public boolean mayHaveNulls() {
        return false;
    }

    @Override
    public boolean areAllValuesNull() {
        return false;
    }

    @Override
    public boolean mayHaveMultivaluedFields() {
        return true;
    }

    @Override
    public boolean doesHaveMultivaluedFields() {
        return values.getPositionCount() > 1;
    }

    @Override
    public MvOrdering mvOrdering() {
        return MvOrdering.UNORDERED;
    }

    @Override
    public IntBlock filter(int... positions) {
        try (var builder = blockFactory().newIntBlockBuilder(positions.length)) {
            for (int pos : positions) {
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendInt(values.getInt(v));
                }
                builder.endPositionEntry();
            }
            return builder.mvOrdering(mvOrdering()).build();
        }
    }

    @Override
    public IntBlock keepMask(BooleanVector mask) {
        if (getPositionCount() == 0) {
            incRef();
            return this;
        }
        if (mask.isConstant()) {
            if (mask.getBoolean(0)) {
                incRef();
                return this;
            }
            return (IntBlock) blockFactory().newConstantNullBlock(getPositionCount());
        }
        try (IntBlock.Builder builder = blockFactory().newIntBlockBuilder(getPositionCount())) {
            for (int p = 0; p < getPositionCount(); p++) {
                if (false == mask.getBoolean(p)) {
                    builder.appendNull();
                    continue;
                }
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendInt(values.getInt(v));
                }
                builder.endPositionEntry();
            }
            return builder.build();
        }
    }

    @Override
    public ReleasableIterator<? extends IntBlock> lookup(IntBlock positions, ByteSizeValue targetBlockSize) {
        // For constant multivalue blocks, we can return ourselves for valid positions
        // but need to handle out-of-bounds positions
        return new IntLookup(this, positions, targetBlockSize);
    }

    @Override
    public IntBlock expand() {
        // Expand creates a block where each value in the multivalue becomes its own position.
        // For a constant multivalue block, each position has the same values, so we need to
        // repeat the values for each position.
        int valueCount = values.getPositionCount();
        int expandedPositionCount = positionCount * valueCount;
        try (IntVector.Builder builder = blockFactory().newIntVectorBuilder(expandedPositionCount)) {
            for (int p = 0; p < positionCount; p++) {
                for (int v = 0; v < valueCount; v++) {
                    builder.appendInt(values.getInt(v));
                }
            }
            return builder.build().asBlock();
        }
    }

    @Override
    public IntBlock deepCopy(BlockFactory blockFactory) {
        return blockFactory.newConstantIntMultivalueBlockWith(values.deepCopy(blockFactory), positionCount);
    }

    @Override
    public long ramBytesUsed() {
        return BASE_RAM_BYTES_USED + values.ramBytesUsed();
    }

    @Override
    public boolean equals(Object obj) {
        if (obj instanceof IntBlock that) {
            return IntBlock.equals(this, that);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return IntBlock.hash(this);
    }

    @Override
    public String toString() {
        return getClass().getSimpleName() + "[positions=" + positionCount + ", values=" + values + ']';
    }

    @Override
    public void closeInternal() {
        blockFactory().adjustBreaker(-BASE_RAM_BYTES_USED);
        Releasables.closeExpectNoException(values);
    }

    @Override
    public void allowPassingToDifferentDriver() {
        values.allowPassingToDifferentDriver();
    }

    @Override
    public BlockFactory blockFactory() {
        return values.blockFactory();
    }
}
