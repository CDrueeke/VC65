.target mega65
.org $2000
.petscii "{clr}Hi{down*2}{rvs on}X{rvs off}{ret}{$c1}{147}"
.petscii "a{{b{RVS_ON}{shift-space}{f1}{$20*3}"
.screen "{$01}{2}ab"
.encoding "petscii" {
    .text "ab{ret}"
    .null "x{ret}y"
    .ptext "a{down*3}b"
    .encoding "screen" {
        .text "ab"
    }
    .text "cd"
}
.text "ab"
