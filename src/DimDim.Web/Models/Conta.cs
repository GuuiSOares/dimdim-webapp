using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DimDim.Web.Models;

public class Conta
{
    public int Id { get; set; }

    [Required, StringLength(100)]
    [Display(Name = "Nome da conta")]
    public string Nome { get; set; } = string.Empty;

    [Required, StringLength(50)]
    [Display(Name = "Instituição")]
    public string Instituicao { get; set; } = string.Empty;

    [Required, StringLength(30)]
    public string Tipo { get; set; } = string.Empty;

    [Column(TypeName = "decimal(18,2)")]
    [Range(typeof(decimal), "-9999999999999999", "9999999999999999")]
    [Display(Name = "Saldo inicial")]
    public decimal SaldoInicial { get; set; }

    public ICollection<Transacao> Transacoes { get; set; } = new List<Transacao>();

    [NotMapped]
    public decimal Saldo => SaldoInicial + Transacoes.Sum(t => t.Tipo == TipoTransacao.Receita ? t.Valor : -t.Valor);
}
