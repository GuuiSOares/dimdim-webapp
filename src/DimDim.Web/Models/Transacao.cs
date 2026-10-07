using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace DimDim.Web.Models;

public enum TipoTransacao { Receita = 1, Despesa = 2 }

public class Transacao
{
    public int Id { get; set; }

    [Required, StringLength(150)]
    [Display(Name = "Descrição")]
    public string Descricao { get; set; } = string.Empty;

    [Required, Column(TypeName = "decimal(18,2)")]
    [Range(0.01, 9999999999999999d)]
    public decimal Valor { get; set; }

    [Required, DataType(DataType.Date)]
    public DateTime Data { get; set; } = DateTime.Today;

    [Required]
    public TipoTransacao Tipo { get; set; }

    [Required, Display(Name = "Conta")]
    public int ContaId { get; set; }

    public Conta? Conta { get; set; }
}
