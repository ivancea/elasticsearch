/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

// begin generated imports
import org.apache.lucene.util.BytesRef;
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
public final class ConstantBytesRefMultivalueBlock extends AbstractNonThreadSafeRefCounted implements BytesRefBlock {

    private static final long BASE_RAM_BYTES_USED = RamUsageEstimator.shallowSizeOfInstance(ConstantBytesRefMultivalueBlock.class);

    private final BytesRefVector values;
    private final int positionCount;

    /**
     * Creates a constant multivalue block.
     * @param values the vector containing the multivalue (owned by this block)
     * @param positionCount the number of positions in this block
     */
    ConstantBytesRefMultivalueBlock(BytesRefVector values, int positionCount) {
        assert values.getPositionCount() > 0 : "multivalue must have at least one value";
        this.values = values;
        this.positionCount = positionCount;
    }

    @Override
    public BytesRefVector asVector() {
        // Cannot return a vector because this block has multivalues
        return null;
    }

    @Override
    public OrdinalBytesRefBlock asOrdinals() {
        return null;
    }

    @Override
    public BytesRef getBytesRef(int valueIndex, BytesRef dest) {
        return values.getBytesRef(valueIndex, dest);
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
        return ElementType.BYTES_REF;
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
    public BytesRefBlock filter(int... positions) {
        BytesRef scratch = new BytesRef();
        try (var builder = blockFactory().newBytesRefBlockBuilder(positions.length)) {
            for (int pos : positions) {
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendBytesRef(values.getBytesRef(v, scratch));
                }
                builder.endPositionEntry();
            }
            return builder.mvOrdering(mvOrdering()).build();
        }
    }

    @Override
    public BytesRefBlock keepMask(BooleanVector mask) {
        if (getPositionCount() == 0) {
            incRef();
            return this;
        }
        if (mask.isConstant()) {
            if (mask.getBoolean(0)) {
                incRef();
                return this;
            }
            return (BytesRefBlock) blockFactory().newConstantNullBlock(getPositionCount());
        }
        BytesRef scratch = new BytesRef();
        try (BytesRefBlock.Builder builder = blockFactory().newBytesRefBlockBuilder(getPositionCount())) {
            for (int p = 0; p < getPositionCount(); p++) {
                if (false == mask.getBoolean(p)) {
                    builder.appendNull();
                    continue;
                }
                builder.beginPositionEntry();
                for (int v = 0; v < values.getPositionCount(); v++) {
                    builder.appendBytesRef(values.getBytesRef(v, scratch));
                }
                builder.endPositionEntry();
            }
            return builder.build();
        }
    }

    @Override
    public ReleasableIterator<? extends BytesRefBlock> lookup(IntBlock positions, ByteSizeValue targetBlockSize) {
        // For constant multivalue blocks, we can return ourselves for valid positions
        // but need to handle out-of-bounds positions
        return new BytesRefLookup(this, positions, targetBlockSize);
    }

    @Override
    public BytesRefBlock expand() {
        // Expand creates a block where each value in the multivalue becomes its own position.
        // For a constant multivalue block, each position has the same values, so we need to
        // repeat the values for each position.
        int valueCount = values.getPositionCount();
        int expandedPositionCount = positionCount * valueCount;
        BytesRef scratch = new BytesRef();
        try (BytesRefVector.Builder builder = blockFactory().newBytesRefVectorBuilder(expandedPositionCount)) {
            for (int p = 0; p < positionCount; p++) {
                for (int v = 0; v < valueCount; v++) {
                    builder.appendBytesRef(values.getBytesRef(v, scratch));
                }
            }
            return builder.build().asBlock();
        }
    }

    @Override
    public BytesRefBlock deepCopy(BlockFactory blockFactory) {
        return blockFactory.newConstantBytesRefMultivalueBlockWith(values.deepCopy(blockFactory), positionCount);
    }

    @Override
    public long ramBytesUsed() {
        return BASE_RAM_BYTES_USED + values.ramBytesUsed();
    }

    @Override
    public boolean equals(Object obj) {
        if (obj instanceof BytesRefBlock that) {
            return BytesRefBlock.equals(this, that);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return BytesRefBlock.hash(this);
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
