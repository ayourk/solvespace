#include "ui.h"

#include "harness.h"

TEST_CASE(parseable) {
    // Every locale in locales.txt must select by its culture name, and its
    // .po file must parse into translations: a message every translation
    // carries comes back changed for each locale but English, which keeps
    // the source text. Checking only that nothing crashed proved nothing.
    CHECK_FALSE(Locales().empty());
    for(auto locale : Locales()) {
        CHECK_TRUE(SetLocale(locale.Culture()));
        const std::string &file = Translate("&File");
        if(locale.language == "en") {
            CHECK_EQ_STR(file, "&File");
        } else {
            CHECK_FALSE(file == "&File");
        }
    }
    SetLocale("en_US");
}
