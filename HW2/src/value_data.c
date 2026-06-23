//
// Created by WavJaby on 2026/3/2.
//

#include "value_data.h"

#include <string.h>

#include "compiler_util.h"

// linkedList_init / linkedList_addp / linkedList_deleteNode / linkedList_freeA / cloneStruct 用法：見 README.md §工具函式速查
bool object_ValueDataListCreate(ObjectType valueType, const ScientificNotation* count, ValueData* valueData) {
    linkedList_init(&valueData->valueList);
    valueData->valueType = valueType;
    valueData->count = (count != NULL) ? sciToInt32(count) : 1;
    /* 宣告數量必須為正 */
    if (valueData->count <= 0) {
        yyerrorf("所宣之數須大於零\n");
        return true;
    }
    return false;
}

bool object_ValueDataListAdd(ValueData* valueData, const Object* obj, const YYLTYPE* tokenLoc) {
    /* 不可超過宣告數量 */
    if ((int)valueData->valueList.length >= valueData->count) {
        yyerrorlf("所列之值多於所宣之數\n", tokenLoc);
        return true;
    }

    /* 型別相容性檢查 */
    ObjectType objValueType = object_getValueType(obj);
    if (valueData->valueType == OBJECT_TYPE_AUTO) {
        /* 元（AUTO）：以首個賦入值決定型別 */
        valueData->valueType = objValueType;
    } else if (valueData->valueType == OBJECT_TYPE_STR) {
        /* 言（STR）在印出語境中作為通用可印容器，接受任意值 */
    } else if (valueData->valueType == OBJECT_TYPE_NUM && ObjectType_isNumber(objValueType)) {
        /* 數（NUM）接受任意數值型別 */
    } else if (valueData->valueType == OBJECT_TYPE_ARRAY) {
        /* 列（ARRAY）僅能以新建陣列初始化 */
        if (objValueType != OBJECT_TYPE_ARRAY) {
            yyerrorlf("所賦之屬『%s』與所宣之屬『%s』不符\n",
                      tokenLoc, objectType2str[objValueType], objectType2str[valueData->valueType]);
            return true;
        }
    } else if (objValueType != valueData->valueType) {
        yyerrorlf("所賦之屬『%s』與所宣之屬『%s』不符\n",
                  tokenLoc, objectType2str[objValueType], objectType2str[valueData->valueType]);
        return true;
    }

    /* 深拷貝後加入清單（freeFlag=0：稍後由 freeA(free) 統一釋放節點外殼） */
    Object* clone = cloneStruct(Object, obj);
    if (obj->type == OBJECT_TYPE_STR && obj->value.str)
        clone->value.str = strdup(obj->value.str);
    if (ObjectType_isNumber(obj->type) && obj->value.number)
        clone->value.number = cloneStruct(ScientificNotation, obj->value.number);
    if (obj->type == OBJECT_TYPE_REGISTER && obj->value.symbol)
        clone->value.symbol = symbol_clone(obj->value.symbol);
    linkedList_addp(&valueData->valueList, 0, clone);
    return false;
}

bool object_ValueDataListAddDefaults(ValueData* valueData, const YYLTYPE* tokenLoc) {
    /* 多值宣告時，未顯式賦值的空位以該型別的零值補滿 */
    while ((int)valueData->valueList.length < valueData->count) {
        Object obj;
        ScientificNotation zero = {.type = I32, .fraction = 0, .fractionLen = 1, .exp = 0};
        switch (valueData->valueType) {
        case OBJECT_TYPE_NUM:
        case OBJECT_TYPE_I32:
        case OBJECT_TYPE_I64:
        case OBJECT_TYPE_F64:
        case OBJECT_TYPE_AUTO:
            obj = object_createNumber(&zero);
            break;
        case OBJECT_TYPE_BOOL:
            obj = object_createBool(false);
            break;
        case OBJECT_TYPE_STR:
            obj = object_createStrConst("");
            break;
        case OBJECT_TYPE_ARRAY:
            obj = object_createArray();
            break;
        default:
            yyerrorlf("『%s』無預設之值\n", tokenLoc, objectType2str[valueData->valueType]);
            return true;
        }
        if (object_ValueDataListAdd(valueData, &obj, tokenLoc)) {
            object_free(&obj);
            return true;
        }
        object_free(&obj);
    }
    return false;
}

Object* object_ValueDataListPop(ValueData* valueData) {
    if (valueData->valueList.length == 0)
        return NULL;
    LinkedListNode* node = valueData->valueList.head->next;
    Object* obj = node->value;
    linkedList_deleteNode(&valueData->valueList, node);
    return obj;
}

bool object_ValueDataListFree(ValueData* valueData) {
    linkedList_freeA(&valueData->valueList, free);
    return false;
}
