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
public final class ConstantBooleanMultivalueBlock extends AbstractNonThreadSafeRefCounted implements BooleanBlock {

    private static final long BASE_RAM_BYTES_USED = RamUsageEstimator.shallowSizeOfInstance(ConstantBooleanMultivalueBlock.class);

    private final BooleanVector values;
    private final int positionCount;

    /**
     * Creates a constant multivalue block.
     * @param values the vector containing the multivalue (owned by this block)
     * @param positionCount the number of positions in this block
     */
    ConstantBooleanMultivalueBlock(BooleanVector values, int positionCount) {
        assert values.getPositionCount() > 0 : "multivalue must have at least one value";
        this.values = values;
        this.positionCount = positionCount;
    }

    @Override
    public BooleanVector asVector() {
        // Cannot return a vector because this block has multivalues
        return null;
    }

    @Override
    public boolean getBoolean(int valueIndex) {
        return values.getBoolean(valueIndex);
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
        return ElementType.BOOLEAN;
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
    public ToMask toMask() {
        // A constant multivalue boolean block has the same values for every position.
        // MV values are collapsed: if all values are true, use true; otherwise false.
        try (BooleanVector.FixedBuilder builder = blockFactory().newBooleanVectorFixedBuilder(positionCount)) {
            boolean allTrue = values.allTrue();
            boolean hasMv = values.getPositionCount() > 1;
            for (int p = 0; p < positionCount; p++) {
                builder.appendBoolean(allTrue);
            }
            return new ToMask(builder.build(), hasMv);
        }
    }

    @Override
    public BooleanBlock filter(int... positions) {
        try (var builder = blockFactory().newBooleanBlockBuilder(positions.length)) {
            for (int pos : positions) {
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendBoolean(values.getBoolean(v));
                }
                builder.endPositionEntry();
            }
            return builder.mvOrdering(mvOrdering()).build();
        }
    }

    @Override
    public BooleanBlock keepMask(BooleanVector mask) {
        if (getPositionCount() == 0) {
            incRef();
            return this;
        }
        if (mask.isConstant()) {
            if (mask.getBoolean(0)) {
                incRef();
                return this;
            }
            return (BooleanBlock) blockFactory().newConstantNullBlock(getPositionCount());
        }
        try (BooleanBlock.Builder builder = blockFactory().newBooleanBlockBuilder(getPositionCount())) {
            for (int p = 0; p < getPositionCount(); p++) {
                if (false == mask.getBoolean(p)) {
                    builder.appendNull();
                    continue;
                }
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendBoolean(values.getBoolean(v));
                }
                builder.endPositionEntry();
            }
            return builder.build();
        }
    }

    @Override
    public ReleasableIterator<? extends BooleanBlock> lookup(IntBlock positions, ByteSizeValue targetBlockSize) {
        // For constant multivalue blocks, we can return ourselves for valid positions
        // but need to handle out-of-bounds positions
        return new BooleanLookup(this, positions, targetBlockSize);
    }

    @Override
    public BooleanBlock expand() {
        // Expand creates a block where each value in the multivalue becomes its own position.
        // For a constant multivalue block, each position has the same values, so we need to
        // repeat the values for each position.
        int valueCount = values.getPositionCount();
        int expandedPositionCount = positionCount * valueCount;
        try (BooleanVector.Builder builder = blockFactory().newBooleanVectorBuilder(expandedPositionCount)) {
            for (int p = 0; p < positionCount; p++) {
                for (int v = 0; v < valueCount; v++) {
                    builder.appendBoolean(values.getBoolean(v));
                }
            }
            return builder.build().asBlock();
        }
    }

    @Override
    public BooleanBlock deepCopy(BlockFactory blockFactory) {
        return blockFactory.newConstantBooleanMultivalueBlockWith(values.deepCopy(blockFactory), positionCount);
    }

    @Override
    public long ramBytesUsed() {
        return BASE_RAM_BYTES_USED + values.ramBytesUsed();
    }

    @Override
    public boolean equals(Object obj) {
        if (obj instanceof BooleanBlock that) {
            return BooleanBlock.equals(this, that);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return BooleanBlock.hash(this);
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
