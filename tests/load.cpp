/*  This file is part of the Vc library.

    Copyright (C) 2009 Matthias Kretz <kretz@kde.org>

    Vc is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    Vc is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with Vc.  If not, see <http://www.gnu.org/licenses/>.

*/

#include <Vc/Vc>
#include "unittest.h"
#include <iostream>

using namespace Vc;

template<typename Vec> void checkAlignment()
{
    unsigned char i = 1;
    Vec a[10];
    unsigned long mask = VectorAlignment - 1;
    if (Vec::Size == 1 && sizeof(typename Vec::EntryType) != VectorAlignment) {
        mask = sizeof(typename Vec::EntryType) - 1;
    }
#ifdef VC_IMPL_AVX
    if (sizeof(typename Vec::EntryType) == 2) {
        mask = sizeof(Vec) - 1;
    }
#endif
    for (i = 0; i < 10; ++i) {
        VERIFY((reinterpret_cast<unsigned long>(&a[i]) & mask) == 0);
    }
    const char *data = reinterpret_cast<const char *>(&a[0]);
    for (i = 0; i < 10; ++i) {
        VERIFY(&data[i * Vec::Size * sizeof(typename Vec::EntryType)] == reinterpret_cast<const char *>(&a[i]));
    }
}

template<typename Vec> void loadArray()
{
    typedef typename Vec::EntryType T;
    typedef typename Vec::IndexType I;

    enum { count = 256 * 1024 / sizeof(T) };
    Vc::Memory<Vec, count> array;
    for (int i = 0; i < count; ++i) {
        array[i] = i;
    }

    const I indexesFromZero(IndexesFromZero);

    const Vec offsets(indexesFromZero);
    for (int i = 0; i < count; i += Vec::Size) {
        const T *const addr = &array[i];
        Vec ii(i);
        ii += offsets;

        Vec a(addr);
        COMPARE(a, ii);

        Vec b = Vec::Zero();
        b.load(addr);
        COMPARE(b, ii);
    }
}

template<typename Vec> void loadArrayShort()
{
    typedef typename Vec::EntryType T;

    enum { count = 32 * 1024 };
    Vc::Memory<Vec, count> array;
    for (int i = 0; i < count; ++i) {
        array[i] = i;
    }

    const Vec &offsets = static_cast<Vec>(ushort_v::IndexesFromZero());
    for (int i = 0; i < count; i += Vec::Size) {
        const T *const addr = &array[i];
        Vec ii(i);
        ii += offsets;

        Vec a(addr);
        COMPARE(a, ii);

        Vec b = Vec::Zero();
        b.load(addr);
        COMPARE(b, ii);
    }
}

template<typename T> struct TypeInfo;
template<> struct TypeInfo<double        > { static const char *string() { return "double"; } };
template<> struct TypeInfo<float         > { static const char *string() { return "float"; } };
template<> struct TypeInfo<int           > { static const char *string() { return "int"; } };
template<> struct TypeInfo<unsigned int  > { static const char *string() { return "uint"; } };
template<> struct TypeInfo<short         > { static const char *string() { return "short"; } };
template<> struct TypeInfo<unsigned short> { static const char *string() { return "ushort"; } };
template<> struct TypeInfo<signed char   > { static const char *string() { return "schar"; } };
template<> struct TypeInfo<unsigned char > { static const char *string() { return "uchar"; } };
template<> struct TypeInfo<double_v      > { static const char *string() { return "double_v"; } };
template<> struct TypeInfo<float_v       > { static const char *string() { return "float_v"; } };
#ifdef VC_IMPL_SSE
template<> struct TypeInfo<sfloat_v      > { static const char *string() { return "sfloat_v"; } };
#endif
template<> struct TypeInfo<int_v         > { static const char *string() { return "int_v"; } };
template<> struct TypeInfo<uint_v        > { static const char *string() { return "uint_v"; } };
#ifndef VC_IMPL_LRBni
template<> struct TypeInfo<short_v       > { static const char *string() { return "short_v"; } };
template<> struct TypeInfo<ushort_v      > { static const char *string() { return "ushort_v"; } };
#endif

template<typename T, typename Current = void> struct SupportedConversions { typedef void Next; };
template<> struct SupportedConversions<float, void>           { typedef double         Next; };
template<> struct SupportedConversions<float, double>         { typedef int            Next; };
template<> struct SupportedConversions<float, int>            { typedef unsigned int   Next; };
template<> struct SupportedConversions<float, unsigned int>   { typedef short          Next; };
template<> struct SupportedConversions<float, short>          { typedef unsigned short Next; };
template<> struct SupportedConversions<float, unsigned short> { typedef signed char    Next; };
template<> struct SupportedConversions<float, signed char>    { typedef unsigned char  Next; };
template<> struct SupportedConversions<float, unsigned char>  { typedef void           Next; };
template<> struct SupportedConversions<int  , void          > { typedef unsigned int   Next; };
template<> struct SupportedConversions<int  , unsigned int  > { typedef short          Next; };
template<> struct SupportedConversions<int  , short         > { typedef unsigned short Next; };
template<> struct SupportedConversions<int  , unsigned short> { typedef signed char    Next; };
template<> struct SupportedConversions<int  , signed char   > { typedef unsigned char  Next; };
template<> struct SupportedConversions<int  , unsigned char > { typedef void           Next; };
template<> struct SupportedConversions<unsigned int, void          > { typedef unsigned short Next; };
template<> struct SupportedConversions<unsigned int, unsigned short> { typedef unsigned char  Next; };
template<> struct SupportedConversions<unsigned int, unsigned char > { typedef void           Next; };
template<> struct SupportedConversions<unsigned short, void          > { typedef unsigned char  Next; };
template<> struct SupportedConversions<unsigned short, unsigned char > { typedef void           Next; };
template<> struct SupportedConversions<         short, void          > { typedef unsigned char  Next; };
template<> struct SupportedConversions<         short, unsigned char > { typedef signed char    Next; };
template<> struct SupportedConversions<         short,   signed char > { typedef void           Next; };

template<typename Vec, typename MemT> struct LoadCvt {
    static void test() {
        typedef typename Vec::EntryType VecT;
        MemT *data = Vc::malloc<MemT, Vc::AlignOnCacheline>(128);
        for (size_t i = 0; i < 128; ++i) {
            data[i] = static_cast<MemT>(i - 64);
        }

        for (size_t i = 0; i < 128 - Vec::Size + 1; ++i) {
            Vec v;
            if (i % (2 * Vec::Size) == 0) {
                v = Vec(&data[i]);
            } else if (i % Vec::Size == 0) {
                v = Vec(&data[i], Vc::Aligned);
            } else {
                v = Vec(&data[i], Vc::Unaligned);
            }
            for (size_t j = 0; j < Vec::Size; ++j) {
                COMPARE(v[j], static_cast<VecT>(data[i + j])) << " " << TypeInfo<MemT>::string();
            }
        }
        for (size_t i = 0; i < 128 - Vec::Size + 1; ++i) {
            Vec v;
            if (i % (2 * Vec::Size) == 0) {
                v.load(&data[i]);
            } else if (i % Vec::Size == 0) {
                v.load(&data[i], Vc::Aligned);
            } else {
                v.load(&data[i], Vc::Unaligned);
            }
            for (size_t j = 0; j < Vec::Size; ++j) {
                COMPARE(v[j], static_cast<VecT>(data[i + j])) << " " << TypeInfo<MemT>::string();
            }
        }

        ADD_PASS() << "loadCvt: load " << TypeInfo<MemT>::string() << "* as " << TypeInfo<Vec>::string();
        LoadCvt<Vec, typename SupportedConversions<VecT, MemT>::Next>::test();
    }
};
template<typename Vec> struct LoadCvt<Vec, void> { static void test() {} };

template<typename Vec> void loadCvt()
{
    typedef typename Vec::EntryType T;
    LoadCvt<Vec, typename SupportedConversions<T>::Next>::test();
}

int main()
{
#if !VC_IMPL_LRBni && !defined(__LRB__)
    runTest(checkAlignment<int_v>);
    runTest(checkAlignment<uint_v>);
    runTest(checkAlignment<float_v>);
    runTest(checkAlignment<double_v>);
    runTest(checkAlignment<short_v>);
    runTest(checkAlignment<ushort_v>);
    runTest(checkAlignment<sfloat_v>);
#endif
    runTest(loadArray<int_v>);
    runTest(loadArray<uint_v>);
    runTest(loadArray<float_v>);
    runTest(loadArray<double_v>);
    runTest(loadArray<sfloat_v>);
    runTest(loadArrayShort<short_v>);
    runTest(loadArrayShort<ushort_v>);

    testAllTypes(loadCvt);
    return 0;
}
