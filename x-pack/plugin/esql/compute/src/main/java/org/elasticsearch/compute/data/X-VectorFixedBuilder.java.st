/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.data;

$if(boolean)$
import org.elasticsearch.common.util.$Array$;

$else$
import org.apache.lucene.util.RamUsageEstimator;
$endif$

/**
 * Builder for {@link $Type$Vector}s that never grows. Prefer this to
 * {@link $Type$VectorBuilder} if you know the precise size up front because
 * it's faster.
 * This class is generated. Do not edit it.
 */
final class $Type$VectorFixedBuilder implements $Type$Vector.FixedBuilder {
    private final BlockFactory blockFactory;
$if(boolean)$
    private $Array$ values;
    private int size;
$else$
    private $type$[] values;
$endif$
    private final long preAdjustedBytes;
    /**
     * The next value to write into. {@code -1} means the vector has already
     * been built.
     */
    private int nextIndex;

    private boolean closed;

    $Type$VectorFixedBuilder(int size, BlockFactory blockFactory) {
        this.blockFactory = blockFactory;
$if(boolean)$
        this.values = new $Array$(size, blockFactory.bigArrays());
        this.size = size;
        preAdjustedBytes = ramBytesUsed(size, this.values);
$else$
        this.values = new $type$[size];
        preAdjustedBytes = ramBytesUsed(size);
$endif$
        blockFactory.adjustBreaker(preAdjustedBytes);
    }

    @Override
    public $Type$VectorFixedBuilder append$Type$($type$ value) {
$if(boolean)$
        if (value) {
            values.set(nextIndex);
        }
$else$
        values[nextIndex] = value;
$endif$
        nextIndex++;
        return this;
    }

    @Override
    public $Type$VectorFixedBuilder append$Type$(int idx, $type$ value) {
$if(boolean)$
        if (value) {
            values.set(idx);
        } else {
            values.clear(idx);
        }
$else$
        values[idx] = value;
$endif$
        return this;
    }

$if(boolean)$
    private static long ramBytesUsed(int size, $Array$ values) {
        return size == 1 ? Constant$Type$Vector.RAM_BYTES_USED : $Type$ArrayVector.ramBytesEstimated(values);
    }

    @Override
    public long estimatedBytes() {
        return ramBytesUsed(size, values);
    }

$else$
    private static long ramBytesUsed(int size) {
        return size == 1
            ? Constant$Type$Vector.RAM_BYTES_USED
            : $Type$ArrayVector.BASE_RAM_BYTES_USED + RamUsageEstimator.alignObjectSize(
                (long) RamUsageEstimator.NUM_BYTES_ARRAY_HEADER + size * $BYTES$
            );
    }

    @Override
    public long estimatedBytes() {
        return ramBytesUsed(values.length);
    }
$endif$

    @Override
    public $Type$Vector build() {
        if (closed) {
            throw new IllegalStateException("already closed");
        }
        closed = true;
        $Type$Vector vector;
        if ($if(boolean)$size$else$values.length$endif$ == 1) {
            vector = blockFactory.newConstant$Type$BlockWith($if(boolean)$values.get(0)$else$values[0]$endif$, 1, preAdjustedBytes).asVector();
        } else {
            vector = blockFactory.new$Type$ArrayVector(values, $if(boolean)$size$else$values.length$endif$, preAdjustedBytes);
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
